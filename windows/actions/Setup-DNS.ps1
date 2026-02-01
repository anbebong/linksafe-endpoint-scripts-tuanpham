#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    LINKSAFE Patch Management - Setup DNS Servers

.DESCRIPTION
    Configure DNS servers for all active network adapters

.PARAMETER DNS1
    Primary DNS server (default: 8.8.8.8)

.PARAMETER DNS2
    Secondary DNS server (default: 8.8.4.4)

.EXAMPLE
    .\Setup-DNS.ps1
    .\Setup-DNS.ps1 -DNS1 "8.8.8.8" -DNS2 "8.8.4.4"
    .\Setup-DNS.ps1 -DNS1 "1.1.1.1" -DNS2 "1.0.0.1"
#>

[CmdletBinding()]
param(
    [string]$DNS1 = "8.8.8.8",
    [string]$DNS2 = "8.8.4.4"
)

# Import logging module
$LibPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib"
$WUModulePath = Join-Path $LibPath "WindowsUpdate.psm1"

if (Test-Path $WUModulePath) {
    Import-Module $WUModulePath -Force -ErrorAction SilentlyContinue
}

# Set up logging aliases if module not loaded
if (-not (Get-Command Write-PatchLog -ErrorAction SilentlyContinue)) {
    function Write-PatchLog {
        param([string]$Message, [string]$Level = 'INFO')
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        Write-Output "LOG:${timestamp}:${Level}:${Message}"
    }
}

if (-not (Get-Command Write-PatchData -ErrorAction SilentlyContinue)) {
    function Write-PatchData {
        param([string]$JsonData)
        Write-Output "DATA:$JsonData"
    }
}

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
# Get active adapters
# ===============================
try {
    $Adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

    if ($Adapters.Count -eq 0) {
        $errorResult = @{
            status = "error"
            data = @{
                message = "No active network adapters found"
            }
        } | ConvertTo-Json -Compress
        
        Write-Output $errorResult
        exit 1
    }

    # ===============================
    # Set DNS for all active adapters
    # ===============================
    $DnsServers = @($DNS1, $DNS2)
    $status = "success"
    $message = ""
    $adapterCount = 0

    Write-PatchLog "Setting DNS servers: Primary=$DNS1, Secondary=$DNS2" -Level INFO

    foreach ($Adapter in $Adapters) {
        try {
            Set-DnsClientServerAddress `
                -InterfaceAlias $Adapter.Name `
                -ServerAddresses $DnsServers `
                -ErrorAction Stop
            
            $adapterCount++
            Write-PatchLog "DNS configured for adapter: $($Adapter.Name)" -Level DEBUG
        } catch {
            $status = "error"
            $message = "Error setting DNS on adapter $($Adapter.Name): $_"
            Write-PatchLog "ERROR: $message" -Level ERROR
            break
        }
    }

    if ($status -eq "success") {
        $message = "DNS servers configured successfully on $adapterCount adapter(s). Primary: $DNS1, Secondary: $DNS2"
        Write-PatchLog "DNS configuration completed successfully" -Level INFO
    }

    # ===============================
    # Return JSON result
    # ===============================
    $result = @{
        status = $status
        data = @{
            message = $message
        }
    } | ConvertTo-Json -Compress

    Write-Output $result

    if ($status -eq "error") {
        exit 1
    } else {
        exit 0
    }

} catch {
    $errorResult = @{
        status = "error"
        data = @{
            message = "Failed to configure DNS servers: $($_.Exception.Message)"
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}
