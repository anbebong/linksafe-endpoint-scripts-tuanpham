# =============================================================================
# LINKSAFE Patch Management - Winget Package Manager Module
# =============================================================================
# PowerShell module for Windows Package Manager (winget) operations
# Handles third-party application updates that Windows Update doesn't cover
# =============================================================================

#Requires -Version 5.1

# =============================================================================
# LOGGING FUNCTIONS (standalone, doesn't depend on WindowsUpdate.psm1)
# =============================================================================

function Write-WingetLog {
    <#
    .SYNOPSIS
        Write log message in prefix format: LOG:timestamp:level:message
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    $logMessage = "LOG:${timestamp}:${Level}:${Message}"
    Write-Output $logMessage
}

# Alias to Write-WingetLog for compatibility
if (-not (Get-Command Write-WingetLog -ErrorAction SilentlyContinue)) {
    Set-Alias -Name Write-WingetLog -Value Write-WingetLog -Scope Script
}

# =============================================================================
# WINGET DETECTION
# =============================================================================

function Test-WingetAvailable {
    <#
    .SYNOPSIS
        Check if winget is available on the system
    #>
    try {
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        return $null -ne $wingetPath
    } catch {
        return $false
    }
}

function Get-WingetPath {
    <#
    .SYNOPSIS
        Get the full path to winget executable
    #>
    try {
        # Try standard locations
        $possiblePaths = @(
            (Get-Command winget -ErrorAction SilentlyContinue).Source,
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe"
        )

        foreach ($path in $possiblePaths) {
            if ($path -and (Test-Path $path)) {
                return $path
            }
        }

        # Try resolving wildcard path
        $appInstallerPath = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*" -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($appInstallerPath) {
            $wingetExe = Join-Path $appInstallerPath.FullName "winget.exe"
            if (Test-Path $wingetExe) {
                return $wingetExe
            }
        }

        return $null
    } catch {
        return $null
    }
}

# =============================================================================
# WINGET UPDATE CHECK
# =============================================================================

function Get-WingetUpdates {
    <#
    .SYNOPSIS
        Get list of available updates from winget
    .DESCRIPTION
        Queries winget for available package updates
    .EXAMPLE
        Get-WingetUpdates
    #>
    [CmdletBinding()]
    param()

    Write-WingetLog "Checking for winget updates..." -Level DEBUG

    if (-not (Test-WingetAvailable)) {
        Write-WingetLog "Winget is not available on this system" -Level WARN
        return @{
            available = $false
            message = "Winget is not installed"
            packages = @()
        }
    }

    try {
        # Run winget upgrade to get list of available updates
        # Use --accept-source-agreements to avoid prompts
        $wingetOutput = winget upgrade --accept-source-agreements 2>&1

        $updates = @()
        $inTable = $false
        $headerParsed = $false
        $nameCol = 0
        $idCol = 0
        $versionCol = 0
        $availableCol = 0
        $sourceCol = 0

        foreach ($line in $wingetOutput) {
            $lineStr = $line.ToString().Trim()

            # Skip empty lines
            if ([string]::IsNullOrWhiteSpace($lineStr)) {
                continue
            }

            # Detect table header (contains "Name" and "Id" and "Version")
            if ($lineStr -match "^Name\s+" -and $lineStr -match "Id\s+" -and $lineStr -match "Version") {
                $headerParsed = $true
                $inTable = $true

                # Parse column positions from header
                $nameCol = 0
                $idCol = $lineStr.IndexOf("Id")
                $versionCol = $lineStr.IndexOf("Version")

                # Find "Available" or "New" column (localization varies)
                if ($lineStr.IndexOf("Available") -ge 0) {
                    $availableCol = $lineStr.IndexOf("Available")
                } elseif ($lineStr.IndexOf("New") -ge 0) {
                    $availableCol = $lineStr.IndexOf("New")
                } else {
                    # Estimate position
                    $availableCol = $versionCol + 15
                }

                $sourceCol = $lineStr.IndexOf("Source")
                if ($sourceCol -lt 0) { $sourceCol = $lineStr.Length }

                continue
            }

            # Skip separator line (dashes)
            if ($lineStr -match "^-+$" -or $lineStr -match "^[-\s]+$") {
                continue
            }

            # Skip summary lines
            if ($lineStr -match "^\d+ upgrades? available" -or
                $lineStr -match "^No installed package" -or
                $lineStr -match "^The following packages") {
                continue
            }

            # Parse data lines
            if ($inTable -and $headerParsed -and $lineStr.Length -gt $idCol) {
                try {
                    # Extract columns based on positions
                    $name = ""
                    $id = ""
                    $currentVersion = ""
                    $availableVersion = ""
                    $source = ""

                    if ($idCol -gt 0 -and $lineStr.Length -ge $idCol) {
                        $name = $lineStr.Substring($nameCol, [Math]::Min($idCol - $nameCol, $lineStr.Length - $nameCol)).Trim()
                    }

                    if ($versionCol -gt $idCol -and $lineStr.Length -ge $versionCol) {
                        $id = $lineStr.Substring($idCol, [Math]::Min($versionCol - $idCol, $lineStr.Length - $idCol)).Trim()
                    }

                    if ($availableCol -gt $versionCol -and $lineStr.Length -ge $availableCol) {
                        $currentVersion = $lineStr.Substring($versionCol, [Math]::Min($availableCol - $versionCol, $lineStr.Length - $versionCol)).Trim()
                    }

                    if ($sourceCol -gt $availableCol -and $lineStr.Length -ge $sourceCol) {
                        $availableVersion = $lineStr.Substring($availableCol, [Math]::Min($sourceCol - $availableCol, $lineStr.Length - $availableCol)).Trim()
                    } elseif ($lineStr.Length -gt $availableCol) {
                        $availableVersion = $lineStr.Substring($availableCol).Trim()
                    }

                    if ($sourceCol -lt $lineStr.Length) {
                        $source = $lineStr.Substring($sourceCol).Trim()
                    }

                    # Skip if we don't have valid id
                    if ([string]::IsNullOrWhiteSpace($id)) {
                        continue
                    }

                    # Clean up version strings (remove any trailing source info)
                    $availableVersion = ($availableVersion -split '\s+')[0]
                    $currentVersion = ($currentVersion -split '\s+')[0]

                    $updates += @{
                        name = $name
                        id = $id
                        current_version = $currentVersion
                        available_version = $availableVersion
                        source = if ($source) { $source } else { "winget" }
                        is_security = $false  # Winget doesn't provide security classification
                    }
                } catch {
                    Write-WingetLog "Failed to parse winget line: $lineStr" -Level DEBUG
                }
            }
        }

        Write-WingetLog "Found $($updates.Count) winget updates"

        return @{
            available = $true
            total = $updates.Count
            packages = $updates
        }

    } catch {
        Write-WingetLog "Error checking winget updates: $_" -Level ERROR
        return @{
            available = $true
            total = 0
            packages = @()
            error = $_.Exception.Message
        }
    }
}

# =============================================================================
# WINGET PACKAGE INSTALLATION
# =============================================================================

function Install-WingetUpdates {
    <#
    .SYNOPSIS
        Install all available winget updates
    .DESCRIPTION
        Upgrades all packages with available updates via winget
    .PARAMETER PackageIds
        Optional: Specific package IDs to update
    .EXAMPLE
        Install-WingetUpdates
        Install-WingetUpdates -PackageIds @("Git.Git", "Microsoft.VisualStudioCode")
    #>
    [CmdletBinding()]
    param(
        [string[]]$PackageIds
    )

    Write-WingetLog "Starting winget updates..."

    if (-not (Test-WingetAvailable)) {
        return @{
            status = "error"
            message = "Winget is not installed"
        }
    }

    $startTime = Get-Date
    $results = @()

    try {
        if ($PackageIds -and $PackageIds.Count -gt 0) {
            # Update specific packages
            foreach ($pkgId in $PackageIds) {
                Write-WingetLog "Updating package: $pkgId"
                $output = winget upgrade --id $pkgId --accept-source-agreements --accept-package-agreements --silent 2>&1
                $exitCode = $LASTEXITCODE

                $results += @{
                    id = $pkgId
                    success = ($exitCode -eq 0)
                    exit_code = $exitCode
                    output = ($output | Out-String)
                }
            }
        } else {
            # Update all packages
            Write-WingetLog "Updating all winget packages..."
            $output = winget upgrade --all --accept-source-agreements --accept-package-agreements --silent 2>&1
            $exitCode = $LASTEXITCODE

            $results += @{
                id = "all"
                success = ($exitCode -eq 0)
                exit_code = $exitCode
                output = ($output | Out-String)
            }
        }

        $endTime = Get-Date
        $duration = [int]($endTime - $startTime).TotalSeconds

        $successCount = ($results | Where-Object { $_.success }).Count
        $status = if ($successCount -eq $results.Count) { "success" }
                  elseif ($successCount -gt 0) { "partial" }
                  else { "failure" }

        return @{
            status = $status
            duration_seconds = $duration
            packages_updated = $results
            success_count = $successCount
            total_count = $results.Count
        }

    } catch {
        Write-WingetLog "Error installing winget updates: $_" -Level ERROR
        return @{
            status = "error"
            message = $_.Exception.Message
        }
    }
}

# =============================================================================
# WINGET PACKAGE INFO
# =============================================================================

function Get-WingetPackageInfo {
    <#
    .SYNOPSIS
        Get information about a specific winget package
    .PARAMETER PackageId
        The package ID to query
    .EXAMPLE
        Get-WingetPackageInfo -PackageId "Git.Git"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId
    )

    if (-not (Test-WingetAvailable)) {
        return @{
            error = "Winget is not installed"
        }
    }

    try {
        $output = winget show --id $PackageId --accept-source-agreements 2>&1 | Out-String

        $info = @{
            id = $PackageId
            raw_output = $output
        }

        # Parse common fields
        if ($output -match "Name:\s*(.+)") {
            $info.name = $Matches[1].Trim()
        }
        if ($output -match "Version:\s*(.+)") {
            $info.version = $Matches[1].Trim()
        }
        if ($output -match "Publisher:\s*(.+)") {
            $info.publisher = $Matches[1].Trim()
        }
        if ($output -match "Description:\s*(.+)") {
            $info.description = $Matches[1].Trim()
        }

        return $info

    } catch {
        return @{
            id = $PackageId
            error = $_.Exception.Message
        }
    }
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

Export-ModuleMember -Function @(
    'Test-WingetAvailable',
    'Get-WingetUpdates',
    'Install-WingetUpdates',
    'Get-WingetPackageInfo'
)
