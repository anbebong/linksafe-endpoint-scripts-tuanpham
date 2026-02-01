#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin biến môi trường trên Windows

.DESCRIPTION
    Thu thập thông tin về các biến môi trường hệ thống
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

# Thu thập thông tin biến môi trường
$envVars = @()
Get-ChildItem env: | ForEach-Object {
    $envVars += [ordered]@{
        name = $_.Name
        value = $_.Value
    }
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        environment_variables = $envVars
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult