#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    LINKSAFE Patch Management - Update Certificates

.DESCRIPTION
    Import or remove certificates from Windows Certificate Store based on a list file

.PARAMETER ListFile
    Name of the certificate list file (default: InstallCerts.txt)
    If not a full path, will search in C:\Program Files (x86)\LancsITIM\var\

.PARAMETER Action
    Action to perform: import (default) or reset

.EXAMPLE
    .\Update-Certs.ps1
    .\Update-Certs.ps1 -ListFile "InstallCerts.txt"
    .\Update-Certs.ps1 -ListFile "custom-certs.txt" -Action import
    .\Update-Certs.ps1 -Action reset
#>

[CmdletBinding()]
param(
    [string]$ListFile = "InstallCerts.txt",
    
    [ValidateSet("import","reset")]
    [string]$Action = "import"
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

# ========================
# CONFIG
# ========================
$BaseCertPath = "C:\Program Files (x86)\LancsITIM\var"
$CertStoreName = "Root"          # Root / CA / My
$CertStoreLoc = "LocalMachine"

# ========================
# CHECK ADMIN
# ========================
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    
    $errorResult = @{
        status = "error"
        data = @{
            message = "Administrator privileges required"
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}

# ========================
# RESOLVE LIST FILE
# ========================
# Nếu không phải path đầy đủ → mặc định trong C:\Program Files (x86)\LancsITIM\var\
if (-not [System.IO.Path]::IsPathRooted($ListFile)) {
    $ListFilePath = Join-Path $BaseCertPath $ListFile
} else {
    $ListFilePath = $ListFile
}

if (-not (Test-Path $ListFilePath)) {
    $errorResult = @{
        status = "error"
        data = @{
            message = "Certificate list file not found: $ListFilePath"
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}

# ========================
# PROCESS CERTIFICATES
# ========================
$importedCount = 0
$removedCount = 0
$skippedCount = 0
$errorCount = 0
$errors = @()
$status = "success"

try {
    # Open certificate store
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        $CertStoreName, $CertStoreLoc
    )
    $store.Open("ReadWrite")
    
    # Process each line in the list file
    $fileContent = Get-Content $ListFilePath -ErrorAction Stop
    
    foreach ($line in $fileContent) {
        $certName = $line.Trim()
        
        # Skip empty / comment line
        if ([string]::IsNullOrWhiteSpace($certName) -or $certName.StartsWith("#")) {
            $skippedCount++
            continue
        }
        
        $certPath = Join-Path $BaseCertPath $certName
        
        if (-not (Test-Path $certPath)) {
            $errorCount++
            $errors += "Certificate file not found: $certPath"
            Write-PatchLog "WARNING: Certificate file not found: $certPath" -Level WARN
            continue
        }
        
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $cert.Import($certPath)
            
            $matched = $store.Certificates | Where-Object {
                $_.Thumbprint -eq $cert.Thumbprint
            }
            
            if ($Action -eq "import") {
                if ($matched) {
                    $skippedCount++
                    Write-PatchLog "SKIP: Certificate already exists ($certName)" -Level DEBUG
                } else {
                    $store.Add($cert)
                    $importedCount++
                    Write-PatchLog "IMPORTED: $certName (Thumbprint: $($cert.Thumbprint))" -Level INFO
                }
            }
            elseif ($Action -eq "reset") {
                if ($matched) {
                    foreach ($c in $matched) {
                        $store.Remove($c)
                    }
                    $removedCount++
                    Write-PatchLog "REMOVED: $certName (Thumbprint: $($cert.Thumbprint))" -Level INFO
                } else {
                    $skippedCount++
                    Write-PatchLog "SKIP: Certificate not found in store ($certName)" -Level DEBUG
                }
            }
        }
        catch {
            $errorCount++
            $errorMsg = "Failed to process $certName : $($_.Exception.Message)"
            $errors += $errorMsg
            Write-PatchLog "ERROR: $errorMsg" -Level ERROR
        }
    }
    
    $store.Close()
    
    # Determine status
    if ($errorCount -gt 0) {
        $status = "error"
    }
    
    # Build result message
    $message = if ($Action -eq "import") {
        if ($importedCount -gt 0) {
            "Imported $importedCount certificate(s). Skipped $skippedCount. Errors: $errorCount"
        } else {
            "No certificates imported. Skipped $skippedCount. Errors: $errorCount"
        }
    } else {
        if ($removedCount -gt 0) {
            "Removed $removedCount certificate(s). Skipped $skippedCount. Errors: $errorCount"
        } else {
            "No certificates removed. Skipped $skippedCount. Errors: $errorCount"
        }
    }
    
    $result = @{
        status = $status
        data = @{
            message = $message
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $result
    
    if ($status -eq "error") {
        exit 1
    } else {
        exit 0
    }
    
} catch {
    $errorResult = @{
        status = "error"
        data = @{
            message = "Failed to process certificates: $($_.Exception.Message)"
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}
