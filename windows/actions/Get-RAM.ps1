#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin RAM trên Windows

.DESCRIPTION
    Thu thập thông tin về RAM và memory trên hệ thống
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

# Thu thập thông tin RAM
$ramModules = @()
$physicalMemory = Get-WmiObject Win32_PhysicalMemory -ErrorAction SilentlyContinue

foreach ($ram in $physicalMemory) {
    $ramModules += [ordered]@{
        bank_label = $ram.BankLabel
        capacity_gb = [math]::Round($ram.Capacity / 1GB, 2)
        manufacturer = $ram.Manufacturer
        part_number = $ram.PartNumber
        speed_mhz = $ram.Speed
        memory_type = $ram.MemoryType
        form_factor = $ram.FormFactor
        serial_number = $ram.SerialNumber
    }
}

# Thu thập thông tin memory usage
$osInfo = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
$memoryUsage = @{
    total_physical_memory_gb = [math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 2)
    free_physical_memory_gb = [math]::Round($osInfo.FreePhysicalMemory / 1MB, 2)
    used_physical_memory_gb = [math]::Round(($osInfo.TotalVisibleMemorySize - $osInfo.FreePhysicalMemory) / 1MB, 2)
    memory_usage_percent = [math]::Round((($osInfo.TotalVisibleMemorySize - $osInfo.FreePhysicalMemory) / $osInfo.TotalVisibleMemorySize) * 100, 2)
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        ram = @{
            modules = $ramModules
            usage = $memoryUsage
        }
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult