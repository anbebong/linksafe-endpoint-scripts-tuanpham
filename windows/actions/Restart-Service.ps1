#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    LINKSAFE Patch Management - Restart Windows Service

.DESCRIPTION
    Restart a Windows service by name. The service will be stopped and then started.

.PARAMETER ServiceName
    Name of the Windows service to restart (required)

.PARAMETER Timeout
    Maximum time to wait for service to stop/start (seconds, default: 60)

.PARAMETER Quiet
    Minimal output

.EXAMPLE
    .\Restart-Service.ps1 -ServiceName "Spooler"
    .\Restart-Service.ps1 -ServiceName "WinRM" -Timeout 120
    .\Restart-Service.ps1 -ServiceName "BITS"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,
    
    [int]$Timeout = 60,
    
    [switch]$Quiet
)

# Import logging module
$LibPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib"
$WUModulePath = Join-Path $LibPath "WindowsUpdate.psm1"

if (Test-Path $WUModulePath) {
    Import-Module $WUModulePath -Force -ErrorAction SilentlyContinue
}

# Set up logging aliases if module not loaded
if (-not (Get-Command Write-PatchLog -ErrorAction SilentlyContinue)) {
    function Write-PatchLog {
        param([string]$Message, [string]$Level = 'INFO')
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        Write-Output "LOG:${timestamp}:${Level}:${Message}"
    }
}

if (-not (Get-Command Write-PatchData -ErrorAction SilentlyContinue)) {
    function Write-PatchData {
        param([string]$JsonData)
        Write-Output "DATA:$JsonData"
    }
}

# Check Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    
    $errorResult = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        status = "error"
        service_name = $ServiceName
        error = "Administrator privileges required"
    }
    
    Write-PatchLog "Administrator privileges required" -Level ERROR
    $jsonResult = $errorResult | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $jsonResult
    exit 1
}

try {
    Write-PatchLog "Restarting service: $ServiceName" -Level INFO
    
    # Check if service exists
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    if (-not $service) {
        $errorResult = @{
            hostname = $env:COMPUTERNAME
            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            status = "error"
            service_name = $ServiceName
            error = "Service not found"
        }
        
        Write-PatchLog "Service not found: $ServiceName" -Level ERROR
        $jsonResult = $errorResult | ConvertTo-Json -Depth 10 -Compress
        Write-PatchData $jsonResult
        exit 1
    }
    
    $startTime = Get-Date
    $initialStatus = $service.Status.ToString()
    $displayName = $service.DisplayName
    $serviceType = $service.ServiceType.ToString()
    
    Write-PatchLog "Service found: $displayName ($ServiceName)" -Level DEBUG
    Write-PatchLog "Current status: $initialStatus" -Level DEBUG
    Write-PatchLog "Service type: $serviceType" -Level DEBUG
    
    # Check if service can be stopped/started
    if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        Write-PatchLog "Service is already stopped, starting service..." -Level INFO
        
        try {
            Start-Service -Name $ServiceName -ErrorAction Stop
            $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, (New-TimeSpan -Seconds $Timeout))
            
            $finalStatus = (Get-Service -Name $ServiceName).Status.ToString()
            
            if ($finalStatus -eq "Running") {
                $status = "success"
                $message = "Service started successfully"
            } else {
                $status = "error"
                $message = "Service failed to start. Current status: $finalStatus"
            }
        } catch {
            $status = "error"
            $message = "Failed to start service: $_"
            $finalStatus = (Get-Service -Name $ServiceName).Status.ToString()
        }
    } else {
        # Service is running or in another state, restart it
        Write-PatchLog "Stopping service..." -Level INFO
        
        try {
            # Stop the service
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, (New-TimeSpan -Seconds $Timeout))
            
            Write-PatchLog "Service stopped, starting service..." -Level INFO
            
            # Start the service
            Start-Service -Name $ServiceName -ErrorAction Stop
            $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, (New-TimeSpan -Seconds $Timeout))
            
            $finalStatus = (Get-Service -Name $ServiceName).Status.ToString()
            
            if ($finalStatus -eq "Running") {
                $status = "success"
                $message = "Service restarted successfully"
            } else {
                $status = "error"
                $message = "Service failed to start after restart. Current status: $finalStatus"
            }
        } catch {
            $status = "error"
            $message = "Failed to restart service: $_"
            $finalStatus = (Get-Service -Name $ServiceName).Status.ToString()
        }
    }
    
    $endTime = Get-Date
    $duration = [int](($endTime - $startTime).TotalSeconds)
    
    $result = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        status = $status
        service_name = $ServiceName
        display_name = $displayName
        service_type = $serviceType
        initial_status = $initialStatus
        final_status = $finalStatus
        duration_seconds = $duration
        message = $message
    }
    
    if ($status -eq "success") {
        Write-PatchLog "Service restart completed successfully" -Level INFO
        Write-PatchLog "Duration: $duration seconds" -Level DEBUG
        Write-PatchLog "Final status: $finalStatus" -Level DEBUG
    } else {
        Write-PatchLog "Service restart failed: $message" -Level ERROR
        Write-PatchLog "Final status: $finalStatus" -Level ERROR
    }
    
    $jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $jsonResult
    
    if ($status -eq "error") {
        exit 1
    } else {
        exit 0
    }
    
} catch {
    $errorResult = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        status = "error"
        service_name = $ServiceName
        error = $_.Exception.Message
        error_type = $_.Exception.GetType().FullName
    }
    
    Write-PatchLog "Service restart error: $_" -Level ERROR
    Write-PatchLog "Error details: $($_.Exception.Message)" -Level ERROR
    
    $jsonResult = $errorResult | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $jsonResult
    
    exit 1
}
