#Requires -Version 5.1
<#
.SYNOPSIS
    Pre-upgrade hook: Check disk space

.DESCRIPTION
    Verifies sufficient disk space before installing updates
    Fails if less than 5GB free on system drive

.NOTES
    Part of LINKSAFE Patch Management
#>

$MinFreeSpaceGB = 5
$SystemDrive = $env:SystemDrive

$disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$SystemDrive'"
$freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)

if ($freeSpaceGB -lt $MinFreeSpaceGB) {
    Write-Error "Insufficient disk space: ${freeSpaceGB}GB free, need ${MinFreeSpaceGB}GB"
    exit 1
}

Write-Host "Disk space check passed: ${freeSpaceGB}GB free"
exit 0
