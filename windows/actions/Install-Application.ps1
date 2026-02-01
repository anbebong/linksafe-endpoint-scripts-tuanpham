#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    LINKSAFE Patch Management - Install Application (MSI/EXE)

.DESCRIPTION
    Install an application from MSI or EXE file silently/unattended

.PARAMETER FileName
    Name of the MSI or EXE installer file
    If not a full path, will search in C:\Program Files (x86)\LancsITIM\var\
    If a full path is provided, it will be used as-is

.PARAMETER InstallArgs
    Additional installation arguments (optional)
    For MSI: Additional msiexec parameters
    For EXE: Additional installer parameters

.PARAMETER WaitTimeout
    Maximum time to wait for installation to complete (seconds, default: 3600)

.PARAMETER Quiet
    Minimal output

.EXAMPLE
    .\Install-Application.ps1 -FileName "installer.msi"
    .\Install-Application.ps1 -FileName "installer.exe"
    .\Install-Application.ps1 -FileName "installer.msi" -InstallArgs "INSTALLDIR=C:\Program Files\MyApp"
    .\Install-Application.ps1 -FileName "C:\full\path\to\installer.exe" -WaitTimeout 1800
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$FileName,
    
    [string]$InstallArgs = "",
    
    [int]$WaitTimeout = 3600,
    
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
        file_name = $FileName
        error = "Administrator privileges required"
    }
    
    Write-PatchLog "Administrator privileges required" -Level ERROR
    $jsonResult = $errorResult | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $jsonResult
    exit 1
}

try {
    # Resolve file path
    # Nếu không phải path đầy đủ → mặc định trong C:\Program Files (x86)\LancsITIM\var\
    if (-not [System.IO.Path]::IsPathRooted($FileName)) {
        $FilePath = Join-Path "C:\Program Files (x86)\LancsITIM\var" $FileName
    } else {
        $FilePath = $FileName
    }
    
    # Check if file exists
    if (-not (Test-Path $FilePath)) {
        $errorResult = @{
            hostname = $env:COMPUTERNAME
            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            status = "error"
            file_name = $FileName
            file_path = $FilePath
            search_directory = "C:\Program Files (x86)\LancsITIM\var"
            error = "File not found"
        }
        
        Write-PatchLog "File not found: $FilePath" -Level ERROR
        Write-PatchLog "Searched in: C:\Program Files (x86)\LancsITIM\var\" -Level DEBUG
        $jsonResult = $errorResult | ConvertTo-Json -Depth 10 -Compress
        Write-PatchData $jsonResult
        exit 1
    }
    
    $fileInfo = Get-Item $FilePath
    $fileExtension = $fileInfo.Extension.ToLower()
    $fileName = $fileInfo.Name
    
    Write-PatchLog "Installing application: $fileName" -Level INFO
    Write-PatchLog "File path: $FilePath" -Level DEBUG
    Write-PatchLog "File size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -Level DEBUG
    
    $startTime = Get-Date
    $exitCode = 0
    $installOutput = ""
    $process = $null
    
    # Determine installer type and prepare command
    if ($fileExtension -eq ".msi") {
        # MSI installer
        Write-PatchLog "Detected MSI installer" -Level DEBUG
        
        $msiArgs = @(
            "/i", "`"$FilePath`"",
            "/quiet",
            "/norestart",
            "/l*v", "`"$env:TEMP\install_$([System.IO.Path]::GetFileNameWithoutExtension($fileName))_$(Get-Date -Format 'yyyyMMddHHmmss').log`""
        )
        
        # Add custom arguments if provided
        if ($InstallArgs) {
            $msiArgs += $InstallArgs -split '\s+'
        }
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        $exitCode = $process.ExitCode
        
    } elseif ($fileExtension -eq ".exe") {
        # EXE installer - try common silent install switches
        Write-PatchLog "Detected EXE installer" -Level DEBUG
        
        # Common silent install parameters for different installers
        # Try /S, /SILENT, /VERYSILENT, /quiet, /q, /s first
        $silentSwitches = @("/S", "/SILENT", "/VERYSILENT", "/quiet", "/q", "/s")
        
        $exeArgs = @()
        $foundSilentSwitch = $false
        
        # Check if InstallArgs already contains a silent switch
        if ($InstallArgs) {
            $argList = $InstallArgs -split '\s+'
            foreach ($arg in $argList) {
                if ($silentSwitches -contains $arg.ToUpper()) {
                    $foundSilentSwitch = $true
                }
            }
        }
        
        # Add silent switch if not provided
        if (-not $foundSilentSwitch) {
            # Try /S first (most common)
            $exeArgs += "/S"
        }
        
        # Add custom arguments if provided
        if ($InstallArgs) {
            $exeArgs += ($InstallArgs -split '\s+')
        }
        
        # Create log file path
        $logFile = "$env:TEMP\install_$([System.IO.Path]::GetFileNameWithoutExtension($fileName))_$(Get-Date -Format 'yyyyMMddHHmmss').log"
        
        # Try to add logging if supported
        if (-not ($exeArgs -match "/L" -or $exeArgs -match "/LOG")) {
            # Some installers support /L for logging
            $exeArgs += "/L", "`"$logFile`""
        }
        
        $process = Start-Process -FilePath $FilePath -ArgumentList $exeArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        $exitCode = $process.ExitCode
        
    } else {
        $errorResult = @{
            hostname = $env:COMPUTERNAME
            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            status = "error"
            file_name = $FileName
            file_path = $FilePath
            file_type = $fileExtension
            error = "Unsupported file type. Only .msi and .exe files are supported"
        }
        
        Write-PatchLog "Unsupported file type: $fileExtension" -Level ERROR
        $jsonResult = $errorResult | ConvertTo-Json -Depth 10 -Compress
        Write-PatchData $jsonResult
        exit 1
    }
    
    $endTime = Get-Date
    $duration = [int](($endTime - $startTime).TotalSeconds)
    
    # Determine installation status
    $status = "success"
    $message = "Installation completed successfully"
    
    # MSI exit codes: 0 = success, 3010 = success but reboot required
    # EXE exit codes vary by installer, but 0 usually means success
    if ($exitCode -eq 0) {
        $status = "success"
        $message = "Installation completed successfully"
    } elseif ($fileExtension -eq ".msi" -and $exitCode -eq 3010) {
        $status = "success"
        $message = "Installation completed successfully, reboot required"
    } elseif ($exitCode -ne 0) {
        $status = "error"
        $message = "Installation failed with exit code: $exitCode"
    }
    
    # Try to find log file
    $logFile = $null
    if ($fileExtension -eq ".msi") {
        $logPattern = "$env:TEMP\install_$([System.IO.Path]::GetFileNameWithoutExtension($fileName))_*.log"
        $logFiles = Get-ChildItem -Path $logPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($logFiles) {
            $logFile = $logFiles[0].FullName
        }
    } else {
        $logPattern = "$env:TEMP\install_$([System.IO.Path]::GetFileNameWithoutExtension($fileName))_*.log"
        $logFiles = Get-ChildItem -Path $logPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($logFiles) {
            $logFile = $logFiles[0].FullName
        }
    }
    
    $result = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        status = $status
        file_name = $FileName
        file_path = $FilePath
        file_type = $fileExtension
        exit_code = $exitCode
        duration_seconds = $duration
        message = $message
        log_file = $logFile
        reboot_required = ($exitCode -eq 3010)
    }
    
    if ($status -eq "success") {
        Write-PatchLog "Installation completed successfully" -Level INFO
        Write-PatchLog "Duration: $duration seconds" -Level DEBUG
        if ($exitCode -eq 3010) {
            Write-PatchLog "Reboot required" -Level WARN
        }
    } else {
        Write-PatchLog "Installation failed: $message" -Level ERROR
        if ($logFile -and (Test-Path $logFile)) {
            Write-PatchLog "Check log file for details: $logFile" -Level DEBUG
        }
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
        file_name = $FileName
        file_path = if ($FilePath) { $FilePath } else { $null }
        error = $_.Exception.Message
        error_type = $_.Exception.GetType().FullName
    }
    
    Write-PatchLog "Installation error: $_" -Level ERROR
    Write-PatchLog "Error details: $($_.Exception.Message)" -Level ERROR
    
    $jsonResult = $errorResult | ConvertTo-Json -Depth 10 -Compress
    Write-PatchData $jsonResult
    
    exit 1
}
