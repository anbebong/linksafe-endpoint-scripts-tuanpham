#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    LINKSAFE Patch Management - Windows Defender Virus Scan

.DESCRIPTION
    Perform virus scan using Windows Defender (Microsoft Defender Antivirus)

.PARAMETER Full
    Perform full system scan (default: quick scan)

.PARAMETER Path
    Custom path to scan (if not specified, performs quick scan)

.PARAMETER UpdateDefinitions
    Update virus definitions before scanning

.PARAMETER History
    List all threat detection history (no scan performed)

.PARAMETER Quiet
    Minimal output

.EXAMPLE
    .\Scan-Virus.ps1
    .\Scan-Virus.ps1 -Full
    .\Scan-Virus.ps1 -Path "C:\Users"
    .\Scan-Virus.ps1 -UpdateDefinitions
    .\Scan-Virus.ps1 -History
#>

[CmdletBinding()]
param(
    [switch]$Full,
    
    [string]$Path,
    
    [switch]$UpdateDefinitions,
    
    [switch]$History,
    
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

# Check if Windows Defender is available
if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
    Write-PatchLog "Windows Defender is not available on this system" -Level ERROR
    exit 1
}

# Check Defender status
$defenderStatus = Get-MpComputerStatus
if ($defenderStatus.RealTimeProtectionEnabled -eq $false) {
    Write-PatchLog "Windows Defender Real-time Protection is disabled" -Level WARN
}

# If History mode, just list all threats and exit
if ($History) {
    Write-PatchLog "Retrieving threat detection history..."
    
    try {
        $allThreats = @(Get-MpThreatDetection)
        
        $historyResult = @{
            hostname = $env:COMPUTERNAME
            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            total_threats = $allThreats.Count
            threats = @($allThreats | ForEach-Object {
                @{
                    action_success = $_.ActionSuccess
                    additional_actions_bitmask = $_.AdditionalActionsBitMask
                    am_product_version = $_.AMProductVersion
                    cleaning_action_id = $_.CleaningActionID
                    current_threat_execution_status_id = $_.CurrentThreatExecutionStatusID
                    detection_id = $_.DetectionID.ToString()
                    detection_source_type_id = $_.DetectionSourceTypeID
                    domain_user = $_.DomainUser
                    initial_detection_time = $_.InitialDetectionTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    last_threat_status_change_time = $_.LastThreatStatusChangeTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    process_name = $_.ProcessName
                    remediation_time = $_.RemediationTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    resources = @($_.Resources)
                    threat_id = $_.ThreatID
                    threat_status_error_code = $_.ThreatStatusErrorCode
                    threat_status_id = $_.ThreatStatusID
                }
            })
        }
        
        Write-PatchLog "Found $($allThreats.Count) threat detection(s) in history"
        
        $jsonResult = $historyResult | ConvertTo-Json -Depth 10 -Compress
        Write-PatchData $jsonResult
        
        exit 0
    } catch {
        Write-PatchLog "Failed to retrieve threat history: $_" -Level ERROR
        
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
}

$startTime = Get-Date

# Update definitions if requested
if ($UpdateDefinitions) {
    Write-PatchLog "Updating virus definitions..."
    
    try {
        Update-MpSignature
        Write-PatchLog "Definitions updated successfully"
    } catch {
        Write-PatchLog "Failed to update definitions: $_" -Level WARN
    }
}

# Determine scan type
$scanType = "Quick"
if ($Full) {
    $scanType = "Full"
} elseif ($Path) {
    $scanType = "CustomPath"
    # Clean up path (remove trailing quotes if any)
    $Path = $Path.Trim('"', "'")
    # Normalize path
    try {
        $Path = (Resolve-Path -Path $Path -ErrorAction Stop).Path
    } catch {
        Write-PatchLog "Path does not exist: $Path" -Level ERROR
        exit 1
    }
}

# Perform scan
Write-PatchLog "Starting $scanType scan..."

try {
    $scanResult = $null
    
    Write-PatchLog "Scan in progress..."
    
    # Start-MpScan runs synchronously and waits for completion
    if ($Full) {
        $scanResult = Start-MpScan -ScanType FullScan
    } elseif ($Path) {
        $scanResult = Start-MpScan -ScanType CustomScan -ScanPath $Path
    } else {
        $scanResult = Start-MpScan -ScanType QuickScan
    }
    
    Write-PatchLog "Scan completed, collecting results..."
    
    $endTime = Get-Date
    $duration = [int](($endTime - $startTime).TotalSeconds)
    
    # Get scan results
    $threats = @(Get-MpThreatDetection | Where-Object {
        $_.InitialDetectionTime -ge $startTime
    })
    
    $threatCount = $threats.Count
    
    # Get fresh defender status after scan
    $finalStatus = Get-MpComputerStatus
    
    # Helper function to handle scan age (4294967295 means never scanned)
    function Get-ScanAge {
        param([object]$ageValue)
        if ($null -eq $ageValue -or $ageValue -eq 4294967295) {
            return $null
        }
        return [double]$ageValue
    }
    
    $result = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        scan_type = $scanType
        scan_path = if ($Path) { $Path } else { $null }
        status = "completed"
        duration_seconds = $duration
        threats_found = $threatCount
        threats = @($threats | ForEach-Object {
            @{
                threat_name = $_.ThreatName
                threat_id = $_.ThreatID
                resources = $_.Resources
                initial_detection = $_.InitialDetectionTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                actions_taken = $_.ActionsTaken
            }
        })
        defender_status = @{
            realtime_protection = $finalStatus.RealTimeProtectionEnabled
            definition_age_days = Get-ScanAge $finalStatus.AntivirusSignatureAge
            quick_scan_age_days = Get-ScanAge $finalStatus.QuickScanAge
            full_scan_age_days = Get-ScanAge $finalStatus.FullScanAge
        }
    }
    
    if ($threatCount -gt 0) {
        Write-PatchLog "Scan completed: $threatCount threat(s) found!" -Level WARN
    } else {
        Write-PatchLog "Scan completed: No threats found"
    }
    Write-PatchLog "Duration: $duration seconds" -Level DEBUG
    
    # Output JSON result
    $jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $jsonResult
    
    # Exit with appropriate code
    if ($threatCount -gt 0) {
        exit 1
    } else {
        exit 0
    }
    
} catch {
    Write-PatchLog "Scan failed: $_" -Level ERROR
    
    # Determine scan type for error output
    $errorScanType = "Quick"
    if ($Full) {
        $errorScanType = "Full"
    } elseif ($Path) {
        $errorScanType = "CustomPath"
    }
    
    $errorResult = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        scan_type = $errorScanType
        status = "error"
        error = $_.Exception.Message
    }
    
    $jsonResult = $errorResult | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $jsonResult
    
    exit 1
}
