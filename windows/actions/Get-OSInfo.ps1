#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin hệ điều hành Windows

.DESCRIPTION
    Thu thập thông tin cơ bản về hệ điều hành Windows
#>

# Nhập các module cần thiết
$LibPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib"
$WUModulePath = Join-Path $LibPath "WindowsUpdate.psm1"

Import-Module $WUModulePath -Force -ErrorAction SilentlyContinue

# Thiết lập alias cho logging
if (Get-Command Write-PatchLog -ErrorAction SilentlyContinue) {
    # Sử dụng function từ module
} else {
    # Sử dụng fallback local
    function Write-PatchLog {
        param([string]$Message, [string]$Level = 'INFO')
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        Write-Output "LOG:${timestamp}:${Level}:${Message}"
    }
}

if (Get-Command Write-PatchData -ErrorAction SilentlyContinue) {
    # Sử dụng function từ module
} else {
    # Sử dụng fallback local
    function Write-PatchData {
        param([string]$JsonData)
        Write-Output "DATA:$JsonData"
    }
}

# Thu thập thông tin hệ điều hành
$osInfo = Get-CimInstance Win32_OperatingSystem

# Lấy thông tin hệ thống cơ bản
$systemInfo = @{
    "os_name" = $osInfo.Caption
    "os_version" = $osInfo.Version
    "os_manufacturer" = $osInfo.Manufacturer
    "system_type" = $osInfo.OSArchitecture
    "build_number" = $osInfo.BuildNumber
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        os_info = $systemInfo
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult