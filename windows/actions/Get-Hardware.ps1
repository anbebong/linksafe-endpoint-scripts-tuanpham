#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin phần cứng Windows

.DESCRIPTION
    Thu thập thông tin về hệ thống máy tính và bo mạch chủ
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

# Thu thập thông tin phần cứng
$computerSystem = Get-WmiObject Win32_ComputerSystem
$baseBoard = Get-WmiObject Win32_BaseBoard

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        hardware = @{
            computer_system = @{
                name = $computerSystem.Name
                manufacturer = $computerSystem.Manufacturer
                model = $computerSystem.Model
                total_physical_memory = $computerSystem.TotalPhysicalMemory
                number_of_processors = $computerSystem.NumberOfProcessors
                number_of_logical_processors = $computerSystem.NumberOfLogicalProcessors
            }
            base_board = @{
                manufacturer = $baseBoard.Manufacturer
                product = $baseBoard.Product
                version = $baseBoard.Version
                serial_number = $baseBoard.SerialNumber
            }
        }
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult