#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    LINKSAFE Patch Management - Install Security Updates Only

.DESCRIPTION
    Convenience wrapper for installing security updates only

.PARAMETER Reboot
    Reboot if required after installation

.EXAMPLE
    .\Install-SecurityUpdates.ps1
    .\Install-SecurityUpdates.ps1 -Reboot
#>

[CmdletBinding()]
param(
    [switch]$Reboot
)

$ScriptPath = Join-Path $PSScriptRoot "Install-Updates.ps1"
& $ScriptPath -SecurityOnly -Reboot:$Reboot
