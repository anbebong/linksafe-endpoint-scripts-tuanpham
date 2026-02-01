#Requires -Version 5.1
<#
.SYNOPSIS
    LINKSAFE Patch Management - List Running Processes

.DESCRIPTION
    List all running processes on the system with detailed information including
    PID, name, CPU usage, memory usage, start time, and user information

.PARAMETER Name
    Filter processes by name (supports wildcards)

.PARAMETER User
    Filter processes by username

.PARAMETER Format
    Output format: 'json' (default) or 'table'

.PARAMETER Quiet
    Minimal output

.EXAMPLE
    .\Get-Processes.ps1
    .\Get-Processes.ps1 -Name "chrome*"
    .\Get-Processes.ps1 -User "DOMAIN\username"
    .\Get-Processes.ps1 -Format table
#>

[CmdletBinding()]
param(
    [string]$Name,
    
    [string]$User,
    
    [ValidateSet('json', 'table')]
    [string]$Format = 'json',
    
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

try {
    Write-PatchLog "Collecting process information..." -Level DEBUG
    
    # Get all processes
    $processes = Get-Process -ErrorAction SilentlyContinue
    
    # Apply filters if specified
    if ($Name) {
        $processes = $processes | Where-Object { $_.ProcessName -like $Name }
    }
    
    if ($User) {
        $processes = $processes | Where-Object { 
            try {
                $owner = (Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).GetOwner()
                if ($owner) {
                    $ownerUser = "$($owner.Domain)\$($owner.User)"
                    $ownerUser -like $User -or $ownerUser -eq $User
                } else {
                    $false
                }
            } catch {
                $false
            }
        }
    }
    
    $processList = @()
    $totalMemory = 0
    $totalCpuTime = 0
    
    foreach ($proc in $processes) {
        try {
            # Get process owner information
            $ownerInfo = $null
            $ownerDomain = $null
            $ownerUser = $null
            
            try {
                $wmiProcess = Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
                if ($wmiProcess) {
                    $owner = $wmiProcess.GetOwner()
                    if ($owner) {
                        $ownerDomain = $owner.Domain
                        $ownerUser = $owner.User
                        $ownerInfo = "$($owner.Domain)\$($owner.User)"
                    }
                }
            } catch {
                # Ignore errors getting owner info
            }
            
            # Get process start time
            $startTime = $null
            try {
                $startTime = $proc.StartTime
            } catch {
                # Some system processes don't allow access to StartTime
            }
            
            # Calculate memory usage in MB
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            $totalMemory += $memoryMB
            
            # Get CPU time
            $cpuTime = $null
            try {
                $cpuTime = $proc.CPU
            } catch {
                # CPU time may not be available for all processes
            }
            
            if ($cpuTime) {
                $totalCpuTime += $cpuTime
            }
            
            # Get process path if available
            $processPath = $null
            try {
                $processPath = $proc.Path
            } catch {
                # Path may not be accessible for some processes
            }
            
            # Get process command line if available
            $commandLine = $null
            try {
                $wmiProcess = Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
                if ($wmiProcess) {
                    $commandLine = $wmiProcess.CommandLine
                }
            } catch {
                # Command line may not be accessible
            }
            
            # Get thread count
            $threadCount = $null
            try {
                $threadCount = $proc.Threads.Count
            } catch {
                # Thread count may not be available
            }
            
            $processInfo = @{
                pid = $proc.Id
                name = $proc.ProcessName
                cpu_time_seconds = if ($cpuTime) { [math]::Round($cpuTime, 2) } else { $null }
                memory_mb = $memoryMB
                start_time = if ($startTime) { $startTime.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
                owner_domain = $ownerDomain
                owner_user = $ownerUser
                owner = $ownerInfo
                path = $processPath
                command_line = $commandLine
                thread_count = $threadCount
                priority = $proc.PriorityClass.ToString()
                responding = $proc.Responding
            }
            
            $processList += $processInfo
        } catch {
            Write-PatchLog "Error processing process $($proc.Id): $_" -Level WARN
        }
    }
    
    $result = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        total_processes = $processList.Count
        total_memory_mb = [math]::Round($totalMemory, 2)
        total_cpu_time_seconds = [math]::Round($totalCpuTime, 2)
        processes = $processList
    }
    
    if (-not $Quiet) {
        Write-PatchLog "Found $($processList.Count) process(es)" -Level INFO
        Write-PatchLog "Total memory usage: $([math]::Round($totalMemory, 2)) MB" -Level INFO
    }
    
    # Output based on format
    if ($Format -eq 'table') {
        Write-Host ""
        Write-Host "--- RUNNING PROCESSES ---" -ForegroundColor Cyan
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
        
        $processList | Format-Table -AutoSize -Property `
            @{Label="PID"; Expression={$_.pid}}, `
            @{Label="Name"; Expression={$_.name}}, `
            @{Label="Memory (MB)"; Expression={$_.memory_mb}}, `
            @{Label="CPU Time (s)"; Expression={$_.cpu_time_seconds}}, `
            @{Label="Owner"; Expression={$_.owner}}, `
            @{Label="Start Time"; Expression={$_.start_time}}, `
            @{Label="Responding"; Expression={$_.responding}}
        
        Write-Host ""
        Write-Host "Total: $($processList.Count) processes" -ForegroundColor Cyan
        Write-Host "Total Memory: $([math]::Round($totalMemory, 2)) MB" -ForegroundColor Cyan
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan
    } else {
        # JSON output
        $jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
        Write-PatchData $jsonResult
    }
    
    exit 0
    
} catch {
    Write-PatchLog "Failed to list processes: $_" -Level ERROR
    
    $errorResult = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        status = "error"
        error = $_.Exception.Message
    }
    
    $jsonResult = $errorResult | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $jsonResult
    
    exit 1
}
