#Requires -Version 5.1
<#
.SYNOPSIS
    Post-upgrade hook: Verify critical services

.DESCRIPTION
    Verifies critical Windows services are running after update

.NOTES
    Part of LINKSAFE Patch Management
#>

$CriticalServices = @(
    "W32Time",
    "EventLog",
    "Winmgmt"
)

$failed = @()

foreach ($service in $CriticalServices) {
    $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne 'Running') {
            Write-Warning "Service not running: $service (Status: $($svc.Status))"
            # Try to start it
            try {
                Start-Service -Name $service -ErrorAction Stop
                Write-Host "Started service: $service"
            } catch {
                $failed += $service
            }
        } else {
            Write-Host "Service OK: $service"
        }
    }
}

if ($failed.Count -gt 0) {
    Write-Warning "Failed to start services: $($failed -join ', ')"
    # Post-upgrade hooks don't fail the process
}

exit 0
