#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin các port mạng đang listening trên Windows

.DESCRIPTION
    Thu thập thông tin về các port TCP đang listening
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

# Thu thập thông tin port listening
$tcpConnections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
$udpEndpoints = Get-NetUDPEndpoint -ErrorAction SilentlyContinue

# Parse TCP connections
$listeningPorts = @()
foreach ($conn in $tcpConnections) {
    $listeningPorts += @{
        protocol = "TCP"
        local_address = $conn.LocalAddress
        local_port = $conn.LocalPort
        state = "LISTENING"
    }
}

# Parse UDP endpoints
foreach ($udp in $udpEndpoints) {
    $listeningPorts += @{
        protocol = "UDP"
        local_address = $udp.LocalAddress
        local_port = $udp.LocalPort
        state = "LISTENING"
    }
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        network_ports = $listeningPorts
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult