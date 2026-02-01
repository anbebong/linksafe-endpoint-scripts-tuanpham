#Requires -Version 5.1
<#
.SYNOPSIS
    LINKSAFE Patch Management - Check Reboot Status

.DESCRIPTION
    Check if Windows requires a reboot

.PARAMETER Quiet
    Exit code only (0=no reboot, 1=reboot required)

.EXAMPLE
    .\Check-Reboot.ps1
    if ($LASTEXITCODE -eq 1) { Write-Host "Reboot required" }
#>

[CmdletBinding()]
param(
    [switch]$Quiet
)

# Import module
$ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib\WindowsUpdate.psm1"
Import-Module $ModulePath -Force

$result = Get-PendingReboot

if (-not $Quiet) {
    Write-Output ($result | ConvertTo-Json -Depth 5)
}

if ($result.reboot_required) {
    exit 1
} else {
    exit 0
}
