#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    LINKSAFE Patch Management - Setup Proxy Settings

.DESCRIPTION
    Configure, reset, or check system-wide proxy settings

.PARAMETER Param1
    First parameter: ProxyIP, "reset", or "check"
    If "reset": Reset proxy settings
    If "check": Check current proxy settings
    Otherwise: Proxy IP address (default: 192.168.100.244)

.PARAMETER Param2
    Second parameter: ProxyPort (default: 8888)
    Only used when Param1 is ProxyIP

.PARAMETER Param3
    Third parameter: NoProxy list (default: "localhost,127.0.0.1,::1,.local,.svc,.cluster.local")
    Only used when Param1 is ProxyIP

.EXAMPLE
    .\Setup-Proxy.ps1
    .\Setup-Proxy.ps1 "192.168.100.244" 8888 "localhost,127.0.0.1"
    .\Setup-Proxy.ps1 reset
    .\Setup-Proxy.ps1 check
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Param1 = "",
    
    [Parameter(Position=1)]
    [string]$Param2 = "",
    
    [Parameter(Position=2)]
    [string]$Param3 = ""
)
echo "Setup-Proxy.ps1 started"
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
# Parse parameters
# ===============================
$Action = "set"
$ProxyIP = "192.168.100.244"
$ProxyPort = 8888
$NoProxy = "localhost,127.0.0.1,::1,.local,.svc,.cluster.local"

if ($Param1 -eq "reset" -or $Param1 -eq "--reset") {
    $Action = "reset"
} elseif ($Param1 -eq "check" -or $Param1 -eq "--check") {
    $Action = "check"
} else {
    if ($Param1) { $ProxyIP = $Param1 }
    if ($Param2) { $ProxyPort = [int]$Param2 }
    if ($Param3) { $NoProxy = $Param3 }
}

$HKLMInternetSettings = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$PolicyPath = "HKLM:\Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings"

# ===============================
# SET PROXY
# ===============================
if ($Action -eq "set") {
    $ProxyServer = "$ProxyIP`:$ProxyPort"
    $ProxyURL = "http://$ProxyServer"
    $NoProxyWindows = $NoProxy -replace ",", ";"
    
    try {
        # WinHTTP (system services)
        netsh winhttp set proxy proxy-server="$ProxyServer" bypass-list="$NoProxyWindows" | Out-Null
        
        # Machine-wide policy
        if (-not (Test-Path $PolicyPath)) {
            New-Item -Path $PolicyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $PolicyPath -Name ProxySettingsPerUser -Value 0 -Type DWord -Force
        
        # Registry (machine-wide)
        Set-ItemProperty -Path $HKLMInternetSettings -Name ProxyEnable -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $HKLMInternetSettings -Name ProxyServer -Value $ProxyServer -Type String -Force
        Set-ItemProperty -Path $HKLMInternetSettings -Name ProxyOverride -Value $NoProxyWindows -Type String -Force
        Set-ItemProperty -Path $HKLMInternetSettings -Name AutoDetect -Value 0 -Type DWord -Force
        
        $message = "Proxy configured successfully: $ProxyURL (NoProxy: $NoProxy)"
        
        $result = @{
            status = "success"
            data = @{
                message = $message
            }
        } | ConvertTo-Json -Compress
        
        Write-Output $result
        exit 0
    } catch {
        $message = "Failed to configure proxy: $($_.Exception.Message)"
        
        $result = @{
            status = "error"
            data = @{
                message = $message
            }
        } | ConvertTo-Json -Compress
        
        Write-Output $result
        exit 1
    }
}

# ===============================
# RESET PROXY
# ===============================
elseif ($Action -eq "reset") {
    try {
        netsh winhttp reset proxy | Out-Null
        Remove-ItemProperty -Path $PolicyPath -Name ProxySettingsPerUser -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $HKLMInternetSettings -Name ProxyEnable -Value 0 -Type DWord -Force
        Remove-ItemProperty -Path $HKLMInternetSettings -Name ProxyServer -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $HKLMInternetSettings -Name ProxyOverride -ErrorAction SilentlyContinue
        
        $message = "Proxy settings have been reset successfully"
        
        $result = @{
            status = "success"
            data = @{
                message = $message
            }
        } | ConvertTo-Json -Compress
        
        Write-Output $result
        exit 0
    } catch {
        $message = "Failed to reset proxy: $($_.Exception.Message)"
        
        $result = @{
            status = "error"
            data = @{
                message = $message
            }
        } | ConvertTo-Json -Compress
        
        Write-Output $result
        exit 1
    }
}

# ===============================
# CHECK PROXY
# ===============================
elseif ($Action -eq "check") {
    $checkData = @{
        winhttp = @{}
        registry = @{}
        policy = @{}
    }
    
    # WinHTTP
    try {
        $winhttpOutput = netsh winhttp show proxy 2>&1
        if ($winhttpOutput -match "Direct access") {
            $checkData.winhttp = @{ enabled = $false; proxy = $null; bypass = $null }
        } else {
            $proxyMatch = [regex]::Match($winhttpOutput, "Proxy Server\s*:\s*(.+)")
            $bypassMatch = [regex]::Match($winhttpOutput, "Bypass List\s*:\s*(.+)")
            $checkData.winhttp = @{
                enabled = $true
                proxy = if ($proxyMatch.Success) { $proxyMatch.Groups[1].Value.Trim() } else { $null }
                bypass = if ($bypassMatch.Success) { $bypassMatch.Groups[1].Value.Trim() } else { $null }
            }
        }
    } catch {
        $checkData.winhttp = @{ error = $_.Exception.Message }
    }
    
    # Registry
    try {
        if (Test-Path $HKLMInternetSettings) {
            $proxyEnable = Get-ItemProperty -Path $HKLMInternetSettings -Name ProxyEnable -ErrorAction SilentlyContinue
            $proxyServer = Get-ItemProperty -Path $HKLMInternetSettings -Name ProxyServer -ErrorAction SilentlyContinue
            $proxyOverride = Get-ItemProperty -Path $HKLMInternetSettings -Name ProxyOverride -ErrorAction SilentlyContinue
            $checkData.registry = @{
                enabled = if ($proxyEnable) { [bool]$proxyEnable.ProxyEnable } else { $false }
                proxy = if ($proxyServer) { $proxyServer.ProxyServer } else { $null }
                bypass = if ($proxyOverride) { $proxyOverride.ProxyOverride } else { $null }
            }
        }
    } catch {
        $checkData.registry = @{ error = $_.Exception.Message }
    }
    
    # Policy
    try {
        if (Test-Path $PolicyPath) {
            $policyPerUser = Get-ItemProperty -Path $PolicyPath -Name ProxySettingsPerUser -ErrorAction SilentlyContinue
            $checkData.policy = @{
                machine_wide = if ($policyPerUser) { [bool]($policyPerUser.ProxySettingsPerUser -eq 0) } else { $null }
            }
        }
    } catch {
        $checkData.policy = @{ error = $_.Exception.Message }
    }
    
    $isEnabled = ($checkData.registry.enabled -eq $true) -or ($checkData.winhttp.enabled -eq $true)
    $proxyValue = $checkData.registry.proxy -or $checkData.winhttp.proxy
    
    # Build message
    $message = if ($isEnabled) {
        "Proxy is enabled. Proxy: $proxyValue"
    } else {
        "Proxy is disabled"
    }
    
    $result = @{
        status = "success"
        data = @{
            message = $message
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $result
    exit 0
}
