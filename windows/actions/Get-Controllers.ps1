#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin Controllers trên Windows

.DESCRIPTION
    Thu thập thông tin về các controller và device trên hệ thống
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

# Thu thập thông tin controllers
$controllers = @()
$pnpEntities = Get-WmiObject Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -and (
        $_.Name -match "controller|Controller|CONTROLLER" -or
        $_.PNPClass -match "controller|Controller|CONTROLLER" -or
        $_.PNPClass -eq "USB" -or
        $_.PNPClass -eq "PCI" -or
        $_.PNPClass -eq "HDC" -or
        $_.PNPClass -eq "SCSIAdapter"
    )
}

foreach ($entity in $pnpEntities) {
    $controllers += [ordered]@{
        name = $entity.Name
        device_id = $entity.DeviceID
        pnp_class = $entity.PNPClass
        manufacturer = $entity.Manufacturer
        status = $entity.Status
        description = $entity.Description
    }
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        controllers = $controllers
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult