#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin hệ thống tệp tin Windows

.DESCRIPTION
    Thu thập thông tin về các ổ đĩa logic
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

# Thu thập thông tin hệ thống tệp tin
$disks = Get-WmiObject Win32_LogicalDisk | Select-Object DeviceID, FileSystem, Size, FreeSpace

# Tạo mảng filesystems
$filesystems = @()
foreach ($disk in $disks) {
    $filesystems += @{
        device_id = $disk.DeviceID
        filesystem = $disk.FileSystem
        size = $disk.Size
        free_space = $disk.FreeSpace
    }
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        filesystems = $filesystems
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult