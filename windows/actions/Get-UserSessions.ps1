#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin tất cả các phiên trên Windows

.DESCRIPTION
    Thu thập thông tin về tất cả các phiên terminal và system sessions
#>

# Nhập các module cần thiết
$LibPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib"
$WUModulePath = Join-Path $LibPath "WindowsUpdate.psm1"

Import-Module $WUModulePath -Force -ErrorAction SilentlyContinue

# Thiết lập alias cho logging
if (Get-Command Write-PatchLog -ErrorAction SilentlyContinue) {
    # Sử dụng function từ module
} else {
    # Sử dụng fallback local
    function Write-PatchLog {
        param([string]$Message, [string]$Level = 'INFO')
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        Write-Output "LOG:${timestamp}:${Level}:${Message}"
    }
}

if (Get-Command Write-PatchData -ErrorAction SilentlyContinue) {
    # Sử dụng function từ module
} else {
    # Sử dụng fallback local
    function Write-PatchData {
        param([string]$JsonData)
        Write-Output "DATA:$JsonData"
    }
}

# Thu thập thông tin phiên đang hoạt động
$qwinstaOutput = qwinsta 2>$null

# Parse qwinsta output - chỉ lấy các phiên đang Active
$qwinstaData = @()
if ($qwinstaOutput) {
    $lines = $qwinstaOutput -split "`n" | Where-Object { $_ -and $_.Trim() }
    if ($lines.Count -gt 1) {
        # Skip header line
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            if ($line) {
                # Parse the line - handle different formats
                # Format 1: SESSIONNAME USERNAME ID STATE TYPE DEVICE (with username)
                # Format 2: SESSIONNAME ID STATE (without username, like services)
                $parts = $line -split '\s+', 6
                if ($parts.Count -ge 3) {
                    $sessionData = @{}
                    
                    # Check if parts[1] is numeric (ID) or text (username)
                    if ($parts[1] -match '^\d+$') {
                        # Format: SESSIONNAME ID STATE (no username)
                        $sessionData.session_name = $parts[0] -replace '^>', ''
                        $sessionData.username = $null
                        $sessionData.id = $parts[1]
                        $sessionData.state = $parts[2]
                        $sessionData.type = if ($parts.Count -gt 3) { $parts[3] } else { $null }
                        $sessionData.device = if ($parts.Count -gt 4) { $parts[4] } else { $null }
                    } else {
                        # Format: SESSIONNAME USERNAME ID STATE TYPE DEVICE
                        $sessionData.session_name = $parts[0] -replace '^>', ''
                        $sessionData.username = $parts[1]
                        $sessionData.id = $parts[2]
                        $sessionData.state = $parts[3]
                        $sessionData.type = if ($parts.Count -gt 4) { $parts[4] } else { $null }
                        $sessionData.device = if ($parts.Count -gt 5) { $parts[5] } else { $null }
                    }
                    
                    $qwinstaData += $sessionData
                }
            }
        }
    }
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        sessions = @($qwinstaData)
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult