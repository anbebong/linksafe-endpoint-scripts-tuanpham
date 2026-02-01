#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin Video/Graphics trên Windows

.DESCRIPTION
    Thu thập thông tin về video controllers và graphics trên hệ thống
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

# Thu thập thông tin video controllers
$videoControllers = @()
$videoCards = Get-WmiObject Win32_VideoController -ErrorAction SilentlyContinue

foreach ($card in $videoCards) {
    $videoControllers += [ordered]@{
        name = $card.Name
        device_id = $card.DeviceID
        adapter_ram_mb = [math]::Round($card.AdapterRAM / 1MB, 0)
        driver_version = $card.DriverVersion
        driver_date = $card.DriverDate
        video_mode_description = $card.VideoModeDescription
        current_horizontal_resolution = $card.CurrentHorizontalResolution
        current_vertical_resolution = $card.CurrentVerticalResolution
        current_refresh_rate = $card.CurrentRefreshRate
        current_bits_per_pixel = $card.CurrentBitsPerPixel
        manufacturer = $card.Manufacturer
        video_processor = $card.VideoProcessor
        status = $card.Status
    }
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        video_graphics = $videoControllers
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult