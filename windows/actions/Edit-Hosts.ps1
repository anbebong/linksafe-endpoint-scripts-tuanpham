## Run Script:
## powershell.exe -ExecutionPolicy Bypass -File Edit-Hosts.ps1 [InputFile]
## Ví dụ: powershell.exe -ExecutionPolicy Bypass -File Edit-Hosts.ps1 C:\Temp\EditHosts.txt
## Mặc định: C:\Program Files (x86)\LancsITIM\var\EditHosts.txt

param(
    [Parameter(Position=0)]
    [string]$InputFile = "C:\Program Files (x86)\LancsITIM\var\EditHosts.txt"
)
echo "InputFile: $InputFile"

# ===============================
# Check Administrator
# ===============================
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    
    $errorResult = @{
        status = "error"
        data = @{
            message = "Administrator privileges required"
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}

# ===============================
# Setup paths
# ===============================
$HostFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$StartMarker = "# start list sync host"
$EndMarker = "# end list sync host"

# Nếu là path tương đối → đặt trong C:\Program Files (x86)\LancsITIM\var
if (-not [System.IO.Path]::IsPathRooted($InputFile)) {
    $InputFile = Join-Path "C:\Program Files (x86)\LancsITIM\var" $InputFile
}

# ===============================
# Check input file exists
# ===============================
if (-not (Test-Path $InputFile)) {
    $errorResult = @{
        status = "error"
        data = @{
            message = "Input file not found: $InputFile"
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}

# ===============================
# Read current hosts file first (to check existing entries)
# ===============================
$existingHostsContent = @()
try {
    if (Test-Path $HostFile) {
        try {
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            $existingHostsContentRaw = [System.IO.File]::ReadAllText($HostFile, $utf8NoBom)
        } catch {
            $existingHostsContentRaw = [System.IO.File]::ReadAllText($HostFile, [System.Text.Encoding]::Default)
        }
        if ($existingHostsContentRaw) {
            $existingHostsContent = $existingHostsContentRaw -split "`r`n|`n|`r"
        }
    }
} catch {
    # If can't read, continue with empty array
    $existingHostsContent = @()
}

# ===============================
# Build new block content (only add entries that don't exist)
# ===============================
$NewBlockLines = @()
$status = "success"
$errorMessage = ""

try {
    $inputContent = Get-Content $InputFile -ErrorAction Stop
    
    foreach ($line in $inputContent) {
        # Skip empty lines and comments
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            continue
        }
        
        # Parse IP and hostname
        $parts = $line -split '\s+', 2
        if ($parts.Count -lt 2) {
            continue
        }
        
        $ip = $parts[0].Trim()
        $targetHost = $parts[1].Trim()
        
        # Validate IP address format
        $ipPattern = '^(\d{1,3}\.){3}\d{1,3}$|^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$'
        if ($ip -notmatch $ipPattern) {
            continue
        }
        
        # Extract hostname from URL if needed (remove http://, https://, and path)
        $hostname = $targetHost
        if ($hostname -match '^https?://') {
            $hostname = $hostname -replace '^https?://', ''
        }
        if ($hostname -match '/') {
            $hostname = $hostname -split '/' | Select-Object -First 1
        }
        
        # Remove port number if present
        if ($hostname -match ':') {
            $hostname = $hostname -split ':' | Select-Object -First 1
        }
        
        # Validate hostname is not empty
        if ([string]::IsNullOrWhiteSpace($hostname)) {
            continue
        }
        
        # Check if entry already exists in hosts file
        $entryPattern = "$ip`t$hostname"
        $entryPatternAlt = "$ip $hostname"
        $existingEntry = $existingHostsContent | Where-Object { 
            $_ -like "*$ip*$hostname*" -or 
            $_ -match "^\s*$ip\s+$hostname\s*$" -or
            $_ -match "^\s*$ip\s+.*\s+$hostname\s*$"
        }
        
        if ($existingEntry) {
            # Entry already exists, skip it
            continue
        }
        
        # Add to block (IP and hostname separated by tab - Windows hosts file standard)
        $NewBlockLines += "$ip`t$hostname"
    }
} catch {
    $status = "error"
    $errorMessage = "Error reading input file: $_"
}

if (-not $status) {
    $errorResult = @{
        status = $status
        data = @{
            message = $errorMessage
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}

# ===============================
# Use existing hosts content (already read above)
# ===============================
$hostsContent = $existingHostsContent

# ===============================
# Check if there are new entries to add
# ===============================
if ($NewBlockLines.Count -eq 0) {
    # No new entries to add, all entries already exist
    $result = @{
        status = "success"
        data = @{
            message = "All entries already exist in hosts file. No changes made."
            host_file = $HostFile
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $result
    exit 0
}

# ===============================
# Backup hosts file (only if we have new entries to add)
# ===============================
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$BackupFile = "${HostFile}.bak.${timestamp}"

try {
    if (Test-Path $HostFile) {
        Copy-Item -Path $HostFile -Destination $BackupFile -Force -ErrorAction Stop
    }
} catch {
    $errorResult = @{
        status = "error"
        data = @{
            message = "Failed to backup hosts file: $_"
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}

# ===============================
# Check if markers exist
# ===============================
$hasStart = $false
$hasEnd = $false

foreach ($line in $hostsContent) {
    if ($line.Trim() -eq $StartMarker) {
        $hasStart = $true
    }
    if ($line.Trim() -eq $EndMarker) {
        $hasEnd = $true
    }
}

# ===============================
# Build new hosts content (preserve original line format)
# ===============================
$newHostsContent = @()
$inBlock = $false

if (-not $hasStart -or -not $hasEnd) {
    # Add markers and new block at the end
    # Preserve original content exactly as is
    $newHostsContent = $hostsContent
    # Add newline if last line doesn't end with newline
    if ($newHostsContent.Count -gt 0 -and $newHostsContent[-1] -ne "") {
        $newHostsContent += ""
    }
    $newHostsContent += $StartMarker
    $newHostsContent += $NewBlockLines
    $newHostsContent += $EndMarker
} else {
    # Replace content between markers while preserving original format
    foreach ($line in $hostsContent) {
        $trimmedLine = $line.Trim()
        
        if ($trimmedLine -eq $StartMarker) {
            $inBlock = $true
            # Keep original line format (including any leading/trailing whitespace)
            $newHostsContent += $line
            # Add new block content
            $newHostsContent += $NewBlockLines
        } elseif ($trimmedLine -eq $EndMarker) {
            $inBlock = $false
            # Keep original line format
            $newHostsContent += $line
        } elseif (-not $inBlock) {
            # Keep original line format exactly as is
            $newHostsContent += $line
        }
        # Skip lines inside the block (they will be replaced by new block)
    }
}

# ===============================
# Write new hosts file
# ===============================
$tempFile = Join-Path $env:TEMP "hosts.new"

try {
    # Get original file permissions and attributes before modifying
    $originalAcl = $null
    $originalAttributes = $null
    if (Test-Path $HostFile) {
        $hostFileInfo = Get-Item $HostFile -ErrorAction SilentlyContinue
        if ($hostFileInfo) {
            # Save original ACL (permissions)
            $originalAcl = Get-Acl $HostFile -ErrorAction SilentlyContinue
            # Save original attributes
            $originalAttributes = $hostFileInfo.Attributes
            # Remove read-only attribute temporarily
            if ($hostFileInfo.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                $hostFileInfo.Attributes = $hostFileInfo.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
            }
        }
    }
    
    # Write file using UTF-8 encoding (no BOM for better compatibility)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $content = $newHostsContent -join "`r`n"
    if (-not $content.EndsWith("`r`n")) {
        $content += "`r`n"
    }
    [System.IO.File]::WriteAllText($tempFile, $content, $utf8NoBom)
    
    # Verify file was written correctly
    if (-not (Test-Path $tempFile)) {
        throw "Temporary file was not created"
    }
    
    # Replace hosts file atomically
    Move-Item -Path $tempFile -Destination $HostFile -Force -ErrorAction Stop
    
    # Verify the hosts file exists and is readable
    if (-not (Test-Path $HostFile)) {
        throw "Hosts file was not created after move operation"
    }
    
    # Restore original permissions (ACL) if we had them
    if ($originalAcl) {
        try {
            Set-Acl -Path $HostFile -AclObject $originalAcl -ErrorAction Stop
        } catch {
            # If restoring ACL fails, set standard hosts file permissions
            # System: FullControl, Administrators: FullControl
            try {
                $acl = Get-Acl $HostFile
                $acl.SetAccessRuleProtection($false, $false)
                $systemAccount = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
                $adminAccount = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
                $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemAccount, "FullControl", "Allow")))
                $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminAccount, "FullControl", "Allow")))
                Set-Acl -Path $HostFile -AclObject $acl -ErrorAction Stop
            } catch {
                Write-Warning "Could not set permissions on hosts file: $_"
            }
        }
    }
    
    # Restore original attributes (but ensure not read-only)
    $hostFileInfo = Get-Item $HostFile
    if ($originalAttributes) {
        $hostFileInfo.Attributes = $originalAttributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
    } else {
        # Ensure file is not read-only
        if ($hostFileInfo.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
            $hostFileInfo.Attributes = $hostFileInfo.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        }
    }
} catch {
    $errorResult = @{
        status = "error"
        data = @{
            message = "Failed to write hosts file: $_"
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}

# ===============================
# Return JSON result
# ===============================
$result = @{
    status = "success"
    data = @{
        message = "Successfully added $($NewBlockLines.Count) new entry/entries to hosts file."
        host_file = $HostFile
        backup = $BackupFile
        entries_added = $NewBlockLines.Count
    }
} | ConvertTo-Json -Compress

Write-Output $result
