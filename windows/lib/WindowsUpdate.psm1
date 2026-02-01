# =============================================================================
# LINKSAFE Patch Management - Windows Update Module
# =============================================================================
# PowerShell module for Windows Update operations
# Reference: Rudder Windows Update implementation patterns
# =============================================================================

#Requires -Version 5.1

# =============================================================================
# CONFIGURATION
# =============================================================================
$Script:LinksafePatchVersion = "1.0.0"
$Script:StateDir = "C:\ProgramData\linksafe-patch"
$Script:LogFile = "C:\ProgramData\linksafe-patch\linksafe-patch.log"
$Script:HistoryDir = "C:\ProgramData\linksafe-patch\history"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

function Write-PatchLog {
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

    # Output in prefix format for parsing: LOG:timestamp:level:message
    $logMessage = "LOG:${timestamp}:${Level}:${Message}"
    Write-Output $logMessage

    # Write to log file
    try {
        if (-not (Test-Path (Split-Path $Script:LogFile -Parent))) {
            New-Item -ItemType Directory -Path (Split-Path $Script:LogFile -Parent) -Force | Out-Null
        }
        Add-Content -Path $Script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Ignore logging errors
    }
}

function Write-PatchData {
    <#
    .SYNOPSIS
        Output JSON data with DATA: prefix
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$JsonData
    )

    # Compact JSON to single line and output with DATA: prefix
    $compactJson = $JsonData -replace '\s+', ' ' -replace '{\s+', '{' -replace '\s+}', '}' -replace '\[\s+', '[' -replace '\s+\]', ']' -replace ',\s+', ','
    Write-Output "DATA:$compactJson"
}

# =============================================================================
# WINDOWS UPDATE SESSION
# =============================================================================

function Get-UpdateSession {
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        return $session
    } catch {
        Write-PatchLog "Failed to create Windows Update session: $_" -Level ERROR
        return $null
    }
}

# =============================================================================
# CHECK UPDATES
# =============================================================================

function Get-AvailableUpdates {
    <#
    .SYNOPSIS
        Get list of available Windows updates
    .DESCRIPTION
        Queries Windows Update for available updates and returns JSON
    .PARAMETER SecurityOnly
        Only return security updates
    .EXAMPLE
        Get-AvailableUpdates
        Get-AvailableUpdates -SecurityOnly
    #>
    [CmdletBinding()]
    param(
        [switch]$SecurityOnly
    )

    Write-PatchLog "Checking for available Windows updates..."

    $session = Get-UpdateSession
    if (-not $session) {
        return @{
            status = "error"
            message = "Failed to create Windows Update session"
        } | ConvertTo-Json -Depth 10
    }

    try {
        $searcher = $session.CreateUpdateSearcher()

        # Search criteria
        $searchCriteria = "IsInstalled=0 and IsHidden=0"
        if ($SecurityOnly) {
            # Filter for security updates (CategoryIDs for security)
            $searchCriteria = "IsInstalled=0 and IsHidden=0 and CategoryIDs contains '0FA1201D-4330-4FA8-8AE9-B877473B6441'"
        }

        Write-PatchLog "Searching with criteria: $searchCriteria" -Level DEBUG
        $searchResult = $searcher.Search($searchCriteria)

        $updates = @()
        $securityCount = 0

        foreach ($update in $searchResult.Updates) {
            $isSecurity = $false

            # Check if security update
            foreach ($category in $update.Categories) {
                if ($category.CategoryID -eq "0FA1201D-4330-4FA8-8AE9-B877473B6441") {
                    $isSecurity = $true
                    $securityCount++
                    break
                }
            }

            # Get KB article IDs
            $kbArticles = @()
            foreach ($kb in $update.KBArticleIDs) {
                $kbArticles += "KB$kb"
            }

            $updates += @{
                title = $update.Title
                kb_articles = $kbArticles
                is_security = $isSecurity
                is_mandatory = $update.IsMandatory
                is_downloaded = $update.IsDownloaded
                size_mb = [math]::Round($update.MaxDownloadSize / 1MB, 2)
                severity = if ($update.MsrcSeverity) { $update.MsrcSeverity } else { "Unknown" }
                reboot_required = $update.RebootRequired
                description = $update.Description
            }
        }

        $result = @{
            hostname = $env:COMPUTERNAME
            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            os = @{
                name = (Get-CimInstance Win32_OperatingSystem).Caption
                version = (Get-CimInstance Win32_OperatingSystem).Version
                package_manager = "WindowsUpdate"
            }
            reboot_required = (Get-PendingReboot).reboot_required
            updates = @{
                total = $updates.Count
                security = $securityCount
                packages = $updates
            }
        }

        Write-PatchLog "Found $($updates.Count) updates ($securityCount security)"
        $jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
        Write-PatchData $jsonResult
        return

    } catch {
        Write-PatchLog "Error searching for updates: $_" -Level ERROR
        $errorResult = @{
            status = "error"
            message = $_.Exception.Message
        } | ConvertTo-Json -Depth 10 -Compress
        Write-PatchData $errorResult
        return
    }
}

function Get-AvailableUpdatesObject {
    <#
    .SYNOPSIS
        Get list of available Windows updates as PowerShell object
    .DESCRIPTION
        Same as Get-AvailableUpdates but returns object instead of JSON output
        Used internally when combining with Winget results
    .PARAMETER SecurityOnly
        Only return security updates
    #>
    [CmdletBinding()]
    param(
        [switch]$SecurityOnly
    )

    Write-PatchLog "Checking for available Windows updates (object mode)..." -Level DEBUG

    $session = Get-UpdateSession
    if (-not $session) {
        return @{
            status = "error"
            message = "Failed to create Windows Update session"
            reboot_required = $false
            updates = @{
                total = 0
                security = 0
                packages = @()
            }
        }
    }

    try {
        $searcher = $session.CreateUpdateSearcher()

        $searchCriteria = "IsInstalled=0 and IsHidden=0"
        if ($SecurityOnly) {
            $searchCriteria = "IsInstalled=0 and IsHidden=0 and CategoryIDs contains '0FA1201D-4330-4FA8-8AE9-B877473B6441'"
        }

        $searchResult = $searcher.Search($searchCriteria)

        $updates = @()
        $securityCount = 0

        foreach ($update in $searchResult.Updates) {
            $isSecurity = $false

            foreach ($category in $update.Categories) {
                if ($category.CategoryID -eq "0FA1201D-4330-4FA8-8AE9-B877473B6441") {
                    $isSecurity = $true
                    $securityCount++
                    break
                }
            }

            $kbArticles = @()
            foreach ($kb in $update.KBArticleIDs) {
                $kbArticles += "KB$kb"
            }

            $updates += @{
                title = $update.Title
                name = $update.Title
                kb_articles = $kbArticles
                is_security = $isSecurity
                is_mandatory = $update.IsMandatory
                is_downloaded = $update.IsDownloaded
                size_mb = [math]::Round($update.MaxDownloadSize / 1MB, 2)
                severity = if ($update.MsrcSeverity) { $update.MsrcSeverity } else { "Unknown" }
                reboot_required = $update.RebootRequired
                description = $update.Description
            }
        }

        return @{
            status = "success"
            reboot_required = (Get-PendingReboot).reboot_required
            updates = @{
                total = $updates.Count
                security = $securityCount
                packages = $updates
            }
        }

    } catch {
        Write-PatchLog "Error searching for updates: $_" -Level ERROR
        return @{
            status = "error"
            message = $_.Exception.Message
            reboot_required = $false
            updates = @{
                total = 0
                security = 0
                packages = @()
            }
        }
    }
}

# =============================================================================
# INSTALL UPDATES
# =============================================================================

function Install-WindowsUpdates {
    <#
    .SYNOPSIS
        Install Windows updates
    .DESCRIPTION
        Downloads and installs available Windows updates
    .PARAMETER SecurityOnly
        Only install security updates
    .PARAMETER KBArticles
        Specific KB articles to install
    .EXAMPLE
        Install-WindowsUpdates
        Install-WindowsUpdates -SecurityOnly
        Install-WindowsUpdates -KBArticles @("KB5001234", "KB5005678")
    #>
    [CmdletBinding()]
    param(
        [switch]$SecurityOnly,
        [string[]]$KBArticles
    )

    Write-PatchLog "Starting Windows Update installation..."

    # Require admin
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return @{
            status = "error"
            message = "Administrator privileges required"
        } | ConvertTo-Json -Depth 10
    }

    $startTime = Get-Date
    $session = Get-UpdateSession

    if (-not $session) {
        return @{
            status = "error"
            message = "Failed to create Windows Update session"
        } | ConvertTo-Json -Depth 10
    }

    try {
        $searcher = $session.CreateUpdateSearcher()

        # Search for updates
        $searchCriteria = "IsInstalled=0 and IsHidden=0"
        if ($SecurityOnly) {
            $searchCriteria = "IsInstalled=0 and IsHidden=0 and CategoryIDs contains '0FA1201D-4330-4FA8-8AE9-B877473B6441'"
        }

        $searchResult = $searcher.Search($searchCriteria)

        if ($searchResult.Updates.Count -eq 0) {
            return @{
                status = "success"
                message = "No updates available"
                packages_updated = @()
                duration_seconds = 0
            } | ConvertTo-Json -Depth 10
        }

        # Create update collection to install
        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

        foreach ($update in $searchResult.Updates) {
            $shouldInstall = $true

            # Filter by KB if specified
            if ($KBArticles -and $KBArticles.Count -gt 0) {
                $shouldInstall = $false
                foreach ($kb in $update.KBArticleIDs) {
                    if ($KBArticles -contains "KB$kb" -or $KBArticles -contains $kb) {
                        $shouldInstall = $true
                        break
                    }
                }
            }

            if ($shouldInstall -and $update.EulaAccepted -eq $false) {
                $update.AcceptEula()
            }

            if ($shouldInstall) {
                $updatesToInstall.Add($update) | Out-Null
            }
        }

        if ($updatesToInstall.Count -eq 0) {
            return @{
                status = "success"
                message = "No matching updates to install"
                packages_updated = @()
                duration_seconds = 0
            } | ConvertTo-Json -Depth 10
        }

        Write-PatchLog "Downloading $($updatesToInstall.Count) updates..."

        # Download updates
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        $downloadResult = $downloader.Download()

        if ($downloadResult.ResultCode -ne 2) {
            Write-PatchLog "Download completed with result code: $($downloadResult.ResultCode)" -Level WARN
        }

        Write-PatchLog "Installing updates..."

        # Install updates
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installResult = $installer.Install()

        $endTime = Get-Date
        $duration = [int]($endTime - $startTime).TotalSeconds

        # Collect results
        $installedUpdates = @()
        for ($i = 0; $i -lt $updatesToInstall.Count; $i++) {
            $update = $updatesToInstall.Item($i)
            $updateResult = $installResult.GetUpdateResult($i)

            $installedUpdates += @{
                title = $update.Title
                result_code = $updateResult.ResultCode
                reboot_required = $updateResult.RebootRequired
            }
        }

        $status = if ($installResult.ResultCode -eq 2) { "success" } else { "partial" }

        $result = @{
            hostname = $env:COMPUTERNAME
            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            status = $status
            result_code = $installResult.ResultCode
            reboot_required = $installResult.RebootRequired
            packages_updated = $installedUpdates
            duration_seconds = $duration
        }

        Write-PatchLog "Installation completed: $status (reboot_required: $($installResult.RebootRequired))"

        # Save to history
        Save-ToHistory -Action "install" -Content ($result | ConvertTo-Json -Depth 10)

        return $result | ConvertTo-Json -Depth 10

    } catch {
        Write-PatchLog "Error installing updates: $_" -Level ERROR
        return @{
            status = "error"
            message = $_.Exception.Message
        } | ConvertTo-Json -Depth 10
    }
}

# =============================================================================
# REBOOT CHECK
# =============================================================================

function Get-PendingReboot {
    <#
    .SYNOPSIS
        Check if system requires a reboot
    .DESCRIPTION
        Checks multiple registry keys and WMI for pending reboot status
    .EXAMPLE
        Get-PendingReboot
    #>
    [CmdletBinding()]
    param()

    Write-PatchLog "Checking pending reboot status..." -Level DEBUG

    $rebootRequired = $false
    $reasons = @()

    # Check Component Based Servicing
    $cbsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    if (Test-Path $cbsPath) {
        $rebootRequired = $true
        $reasons += "Component Based Servicing reboot pending"
    }

    # Check Windows Update
    $wuPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    if (Test-Path $wuPath) {
        $rebootRequired = $true
        $reasons += "Windows Update reboot required"
    }

    # Check Pending File Rename Operations
    $pfroPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    try {
        $pfro = Get-ItemProperty -Path $pfroPath -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pfro.PendingFileRenameOperations) {
            $rebootRequired = $true
            $reasons += "Pending file rename operations"
        }
    } catch {
        # Ignore
    }

    # Check Computer Rename Pending
    $renamePathActive = "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName"
    $renamePathPending = "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName"
    try {
        $activeComputerName = (Get-ItemProperty -Path $renamePathActive -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
        $pendingComputerName = (Get-ItemProperty -Path $renamePathPending -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
        if ($activeComputerName -ne $pendingComputerName) {
            $rebootRequired = $true
            $reasons += "Computer rename pending"
        }
    } catch {
        # Ignore
    }

    # Check SCCM Client
    try {
        $sccmReboot = Invoke-CimMethod -Namespace 'ROOT\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' -MethodName 'DetermineIfRebootPending' -ErrorAction SilentlyContinue
        if ($sccmReboot -and $sccmReboot.RebootPending) {
            $rebootRequired = $true
            $reasons += "SCCM client reboot pending"
        }
    } catch {
        # SCCM not installed, ignore
    }

    $result = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        reboot_required = $rebootRequired
        reasons = $reasons
    }

    return $result
}

# =============================================================================
# INSTALLED UPDATES
# =============================================================================

function Get-InstalledKBs {
    <#
    .SYNOPSIS
        Get list of installed Windows updates/hotfixes
    .DESCRIPTION
        Returns list of installed KBs
    .PARAMETER Limit
        Maximum number of results
    .EXAMPLE
        Get-InstalledKBs
        Get-InstalledKBs -Limit 50
    #>
    [CmdletBinding()]
    param(
        [int]$Limit = 100
    )

    Write-PatchLog "Listing installed updates..."

    try {
        $hotfixes = Get-HotFix | Select-Object -First $Limit | ForEach-Object {
            @{
                hotfix_id = $_.HotFixID
                description = $_.Description
                installed_on = if ($_.InstalledOn) { $_.InstalledOn.ToString("yyyy-MM-dd") } else { "Unknown" }
                installed_by = $_.InstalledBy
            }
        }

        $result = @{
            hostname = $env:COMPUTERNAME
            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            total = $hotfixes.Count
            hotfixes = $hotfixes
        }

        return $result | ConvertTo-Json -Depth 10

    } catch {
        Write-PatchLog "Error listing installed updates: $_" -Level ERROR
        return @{
            status = "error"
            message = $_.Exception.Message
        } | ConvertTo-Json -Depth 10
    }
}

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

function Save-ToHistory {
    param(
        [string]$Action,
        [string]$Content
    )

    try {
        if (-not (Test-Path $Script:HistoryDir)) {
            New-Item -ItemType Directory -Path $Script:HistoryDir -Force | Out-Null
        }

        $dateStr = Get-Date -Format "yyyy-MM-dd"
        $timeStr = Get-Date -Format "HHmmss"
        $fileName = "$dateStr-$Action-$timeStr.json"

        Set-Content -Path (Join-Path $Script:HistoryDir $fileName) -Value $Content -Force
    } catch {
        Write-PatchLog "Failed to save history: $_" -Level WARN
    }
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

Export-ModuleMember -Function @(
    'Get-AvailableUpdates',
    'Get-AvailableUpdatesObject',
    'Install-WindowsUpdates',
    'Get-PendingReboot',
    'Get-InstalledKBs',
    'Write-PatchLog',
    'Write-PatchData'
)
