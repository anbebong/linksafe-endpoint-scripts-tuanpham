#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin Sound/Audio trên Windows

.DESCRIPTION
    Thu thập thông tin về sound devices và audio trên hệ thống
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

# Thu thập thông tin sound devices
$soundDevices = @()
$soundCards = Get-WmiObject Win32_SoundDevice -ErrorAction SilentlyContinue

foreach ($device in $soundCards) {
    $soundDevices += [ordered]@{
        name = $device.Name
        device_id = $device.DeviceID
        manufacturer = $device.Manufacturer
        product_name = $device.ProductName
        status = $device.Status
        status_info = $device.StatusInfo
        pnp_device_id = $device.PNPDeviceID
        hardware_id = $device.HardwareID
        driver_provider_name = $device.DriverProviderName
        driver_version = $device.DriverVersion
        driver_date = $device.DriverDate
    }
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        sound_audio = $soundDevices
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult