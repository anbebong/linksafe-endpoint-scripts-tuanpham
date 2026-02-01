#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin Storage trên Windows

.DESCRIPTION
    Thu thập thông tin về disks, partitions và filesystem trên hệ thống
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

# Thu thập thông tin physical disks
$physicalDisks = @()
$diskDrives = Get-WmiObject Win32_DiskDrive -ErrorAction SilentlyContinue

foreach ($disk in $diskDrives) {
    $physicalDisks += [ordered]@{
        device_id = $disk.DeviceID
        model = $disk.Model
        size_gb = [math]::Round($disk.Size / 1GB, 2)
        interface_type = $disk.InterfaceType
        media_type = $disk.MediaType
        serial_number = $disk.SerialNumber
        firmware_revision = $disk.FirmwareRevision
        status = $disk.Status
    }
}

# Thu thập thông tin logical disks
$logicalDisks = @()
$logicalDrives = Get-WmiObject Win32_LogicalDisk -ErrorAction SilentlyContinue

foreach ($drive in $logicalDrives) {
    $logicalDisks += [ordered]@{
        device_id = $drive.DeviceID
        volume_name = $drive.VolumeName
        filesystem = $drive.FileSystem
        size_gb = [math]::Round($drive.Size / 1GB, 2)
        free_space_gb = [math]::Round($drive.FreeSpace / 1GB, 2)
        used_space_gb = [math]::Round(($drive.Size - $drive.FreeSpace) / 1GB, 2)
        usage_percent = if ($drive.Size -gt 0) { [math]::Round((($drive.Size - $drive.FreeSpace) / $drive.Size) * 100, 2) } else { 0 }
        drive_type = $drive.DriveType
        description = $drive.Description
    }
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        storage = @{
            physical_disks = $physicalDisks
            logical_disks = $logicalDisks
        }
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult