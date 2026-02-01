#Requires -Version 5.1
<#
.SYNOPSIS
    LINKSAFE Patch Management - List Installed Updates

.DESCRIPTION
    List installed Windows updates/hotfixes

.PARAMETER Limit
    Maximum number of results (default: 100)

.PARAMETER Filter
    Filter by KB number

.EXAMPLE
    .\Get-InstalledKB.ps1
    .\Get-InstalledKB.ps1 -Limit 50
    .\Get-InstalledKB.ps1 -Filter "KB5001"
#>

[CmdletBinding()]
param(
    [int]$Limit = 100,
    [string]$Filter
)

# Import module
$ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib\WindowsUpdate.psm1"
Import-Module $ModulePath -Force

$result = Get-InstalledKBs -Limit $Limit

# Apply filter if specified
if ($Filter) {
    $resultObj = $result | ConvertFrom-Json
    $filtered = $resultObj.hotfixes | Where-Object { $_.hotfix_id -like "*$Filter*" }

    $filteredResult = @{
        hostname = $resultObj.hostname
        timestamp = $resultObj.timestamp
        filter = $Filter
        total = $filtered.Count
        hotfixes = $filtered
    }

    Write-Output ($filteredResult | ConvertTo-Json -Depth 5)
} else {
    Write-Output $result
}
