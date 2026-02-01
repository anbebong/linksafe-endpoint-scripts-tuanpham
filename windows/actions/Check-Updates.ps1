#Requires -Version 5.1
<#
.SYNOPSIS
    LINKSAFE Patch Management - Check Windows Updates

.DESCRIPTION
    List available Windows updates and optionally third-party app updates via Winget

.PARAMETER SecurityOnly
    Only list security updates (Windows Update only)

.PARAMETER IncludeWinget
    Include third-party application updates from Winget

.PARAMETER WingetOnly
    Only check Winget updates (skip Windows Update)

.PARAMETER Quiet
    Minimal output (JSON only)

.EXAMPLE
    .\Check-Updates.ps1
    .\Check-Updates.ps1 -SecurityOnly
    .\Check-Updates.ps1 -IncludeWinget
    .\Check-Updates.ps1 -WingetOnly
#>

[CmdletBinding()]
param(
    [switch]$SecurityOnly,
    [switch]$IncludeWinget,
    [switch]$WingetOnly,
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

if ($IncludeWinget -or $WingetOnly) {
    if (Test-Path $WingetModulePath) {
        Import-Module $WingetModulePath -Force -ErrorAction SilentlyContinue
    }
}

# Run checks
if (-not $Quiet) {
    Write-PatchLog "Starting update check..."
}

if ($WingetOnly) {
    # Only check Winget
    if (-not $Quiet) {
        Write-PatchLog "Checking Winget updates only..."
    }

    $wingetResult = Get-WingetUpdates

    $result = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        os = @{
            name = (Get-CimInstance Win32_OperatingSystem).Caption
            version = (Get-CimInstance Win32_OperatingSystem).Version
            package_manager = "Winget"
        }
        reboot_required = $false
        updates = @{
            total = $wingetResult.total
            security = 0
            packages = $wingetResult.packages
        }
        winget = @{
            available = $wingetResult.available
            total = $wingetResult.total
        }
    }

    Write-PatchLog "Found $($wingetResult.total) Winget updates"
    $jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $jsonResult

} elseif ($IncludeWinget) {
    # Check both Windows Update and Winget
    if (-not $Quiet) {
        Write-PatchLog "Checking Windows Update and Winget..."
    }

    # Get Windows Updates (this outputs its own DATA:)
    # We need to capture it differently
    $wuResult = Get-AvailableUpdatesObject -SecurityOnly:$SecurityOnly

    # Get Winget updates
    $wingetResult = Get-WingetUpdates

    # Combine results
    $allPackages = @()

    # Add Windows Update packages with source marker
    foreach ($pkg in $wuResult.updates.packages) {
        $pkg.source = "WindowsUpdate"
        $allPackages += $pkg
    }

    # Add Winget packages with source marker
    foreach ($pkg in $wingetResult.packages) {
        $pkg.source = "Winget"
        $allPackages += $pkg
    }

    $result = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        os = @{
            name = (Get-CimInstance Win32_OperatingSystem).Caption
            version = (Get-CimInstance Win32_OperatingSystem).Version
            package_manager = "WindowsUpdate+Winget"
        }
        reboot_required = $wuResult.reboot_required
        updates = @{
            total = $wuResult.updates.total + $wingetResult.total
            security = $wuResult.updates.security
            packages = $allPackages
        }
        windows_update = @{
            total = $wuResult.updates.total
            security = $wuResult.updates.security
        }
        winget = @{
            available = $wingetResult.available
            total = $wingetResult.total
        }
    }

    Write-PatchLog "Found $($wuResult.updates.total) Windows updates + $($wingetResult.total) Winget updates"
    $jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $jsonResult

} else {
    # Standard Windows Update only
    Get-AvailableUpdates -SecurityOnly:$SecurityOnly
}
