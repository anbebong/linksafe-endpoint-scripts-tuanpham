#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    LINKSAFE Patch Management - Install Windows Updates

.DESCRIPTION
    Download and install Windows updates and optionally Winget packages

.PARAMETER SecurityOnly
    Only install security updates (Windows Update only)

.PARAMETER KBArticles
    Specific KB articles to install (Windows Update)

.PARAMETER IncludeWinget
    Also install available Winget updates

.PARAMETER WingetOnly
    Only install Winget updates (skip Windows Update)

.PARAMETER WingetPackages
    Specific Winget package IDs to update

.PARAMETER Reboot
    Reboot if required after installation

.PARAMETER Quiet
    Minimal output

.EXAMPLE
    .\Install-Updates.ps1
    .\Install-Updates.ps1 -SecurityOnly
    .\Install-Updates.ps1 -KBArticles @("KB5001234")
    .\Install-Updates.ps1 -IncludeWinget
    .\Install-Updates.ps1 -WingetOnly
    .\Install-Updates.ps1 -WingetPackages @("Git.Git", "Microsoft.VisualStudioCode")
    .\Install-Updates.ps1 -Reboot
#>

[CmdletBinding()]
param(
    [switch]$SecurityOnly,
    [string[]]$KBArticles,
    [switch]$IncludeWinget,
    [switch]$WingetOnly,
    [string[]]$WingetPackages,
    [switch]$Reboot,
    [switch]$Quiet
)

# =============================================================================
# LOCAL LOGGING FUNCTIONS (fallback if module not loaded)
# =============================================================================
function Local:Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    Write-Output "LOG:${timestamp}:${Level}:${Message}"
}

function Local:Write-Data {
    param([string]$JsonData)
    Write-Output "DATA:${JsonData}"
}

# Import modules
$LibPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib"
$WUModulePath = Join-Path $LibPath "WindowsUpdate.psm1"
$WingetModulePath = Join-Path $LibPath "Winget.psm1"

Import-Module $WUModulePath -Force -ErrorAction SilentlyContinue

# Set up logging aliases based on what's available
if (Get-Command Write-PatchLog -ErrorAction SilentlyContinue) {
    # Use module function
} else {
    # Use local fallback
    Set-Alias -Name Write-PatchLog -Value Local:Write-Log -Scope Script
}

if (Get-Command Write-PatchData -ErrorAction SilentlyContinue) {
    # Use module function
} else {
    # Use local fallback
    Set-Alias -Name Write-PatchData -Value Local:Write-Data -Scope Script
}

if ($IncludeWinget -or $WingetOnly -or $WingetPackages) {
    if (Test-Path $WingetModulePath) {
        Import-Module $WingetModulePath -Force -ErrorAction SilentlyContinue
    }
}

# Run pre-upgrade hooks
$HooksDir = Join-Path (Split-Path $PSScriptRoot -Parent) "hooks.d\pre-upgrade"
if (Test-Path $HooksDir) {
    Get-ChildItem $HooksDir -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
        if (-not $Quiet) {
            Write-PatchLog "Running pre-upgrade hook: $($_.Name)"
        }
        try {
            & $_.FullName
            if ($LASTEXITCODE -ne 0) {
                Write-PatchLog "Pre-upgrade hook failed: $($_.Name)" -Level ERROR
                exit 1
            }
        } catch {
            Write-PatchLog "Pre-upgrade hook error: $_" -Level ERROR
            exit 1
        }
    }
}

# Install updates
if (-not $Quiet) {
    Write-PatchLog "Starting update installation..."
}

$startTime = Get-Date
$wuResult = $null
$wingetResult = $null
$rebootRequired = $false

# Windows Update installation
if (-not $WingetOnly) {
    if (-not $Quiet) {
        Write-PatchLog "Installing Windows Updates..."
    }

    $installParams = @{}
    if ($SecurityOnly) { $installParams['SecurityOnly'] = $true }
    if ($KBArticles) { $installParams['KBArticles'] = $KBArticles }

    $wuResult = Install-WindowsUpdates @installParams
    
    # Extract JSON from output (may contain LOG messages)
    $jsonLine = $wuResult | Where-Object { $_ -match '^\s*\{' -or $_ -match '^DATA:' } | Select-Object -Last 1
    if ($jsonLine -match '^DATA:') {
        $jsonLine = $jsonLine -replace '^DATA:', ''
    }
    
    if ($jsonLine) {
        try {
            $wuResultObj = $jsonLine | ConvertFrom-Json
            if ($wuResultObj.reboot_required) {
                $rebootRequired = $true
            }
        } catch {
            Write-PatchLog "Failed to parse Windows Update result: $_" -Level ERROR
            $wuResultObj = @{
                status = "error"
                message = "Failed to parse result"
                reboot_required = $false
            }
        }
    } else {
        Write-PatchLog "No JSON output found from Windows Update installation" -Level WARN
        $wuResultObj = @{
            status = "error"
            message = "No valid output"
            reboot_required = $false
        }
    }
}

# Winget installation
if ($WingetOnly -or $IncludeWinget -or $WingetPackages) {
    if (-not $Quiet) {
        Write-PatchLog "Installing Winget updates..."
    }

    if (Test-WingetAvailable) {
        if ($WingetPackages -and $WingetPackages.Count -gt 0) {
            $wingetResult = Install-WingetUpdates -PackageIds $WingetPackages
        } else {
            $wingetResult = Install-WingetUpdates
        }
    } else {
        Write-PatchLog "Winget is not available on this system" -Level WARN
        $wingetResult = @{
            status = "skipped"
            message = "Winget not available"
        }
    }
}

$endTime = Get-Date
$duration = [int]($endTime - $startTime).TotalSeconds

# Combine results
if ($WingetOnly) {
    # Winget only output
    $result = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        status = $wingetResult.status
        duration_seconds = $duration
        reboot_required = $false
        winget = $wingetResult
    } | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $result
} elseif ($IncludeWinget -or $WingetPackages) {
    # Combined output
    $combinedStatus = "success"
    if ($wuResultObj.status -eq "failure" -or $wingetResult.status -eq "failure") {
        $combinedStatus = "partial"
    }
    if ($wuResultObj.status -eq "failure" -and $wingetResult.status -eq "failure") {
        $combinedStatus = "failure"
    }

    $result = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        status = $combinedStatus
        duration_seconds = $duration
        reboot_required = $rebootRequired
        windows_update = $wuResultObj
        winget = $wingetResult
    } | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $result
} else {
    # Windows Update only - output JSON result
    if ($wuResultObj) {
        $result = $wuResultObj | ConvertTo-Json -Depth 10 -Compress
        Write-PatchData $result
    } else {
        # Fallback: try to extract JSON from raw output
        $jsonLine = $wuResult | Where-Object { $_ -match '^\s*\{' -or $_ -match '^DATA:' } | Select-Object -Last 1
        if ($jsonLine -match '^DATA:') {
            $jsonLine = $jsonLine -replace '^DATA:', ''
        }
        if ($jsonLine) {
            Write-PatchData $jsonLine
        } else {
            Write-PatchData ($wuResultObj | ConvertTo-Json -Depth 10 -Compress)
        }
    }
}

# Run post-upgrade hooks
$PostHooksDir = Join-Path (Split-Path $PSScriptRoot -Parent) "hooks.d\post-upgrade"
if (Test-Path $PostHooksDir) {
    Get-ChildItem $PostHooksDir -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
        if (-not $Quiet) {
            Write-PatchLog "Running post-upgrade hook: $($_.Name)"
        }
        try {
            & $_.FullName
        } catch {
            Write-PatchLog "Post-upgrade hook error (continuing): $_" -Level WARN
        }
    }
}

# Handle reboot
if ($Reboot -and $rebootRequired) {
    if (-not $Quiet) {
        Write-PatchLog "Reboot required, initiating restart..."
    }

    # Run pre-reboot hooks
    $RebootHooksDir = Join-Path (Split-Path $PSScriptRoot -Parent) "hooks.d\pre-reboot"
    if (Test-Path $RebootHooksDir) {
        Get-ChildItem $RebootHooksDir -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
            if (-not $Quiet) {
                Write-PatchLog "Running pre-reboot hook: $($_.Name)"
            }
            try {
                & $_.FullName
                if ($LASTEXITCODE -ne 0) {
                    Write-PatchLog "Pre-reboot hook failed, aborting reboot" -Level ERROR
                    exit 1
                }
            } catch {
                Write-PatchLog "Pre-reboot hook error, aborting reboot: $_" -Level ERROR
                exit 1
            }
        }
    }

    Restart-Computer -Force
}
