## Run Script:
## powershell.exe -ExecutionPolicy Bypass -File Firewall-Rules.ps1 [InputFile]
## powershell.exe -ExecutionPolicy Bypass -File Firewall-Rules.ps1 reset
## Ví dụ: powershell.exe -ExecutionPolicy Bypass -File Firewall-Rules.ps1 FirewallDrop.txt
## Mặc định: C:\Program Files (x86)\LancsITIM\var\FirewallDrop.txt
##
## Format file FirewallDrop.txt:
##   IP:PORT:DIRECTION (ví dụ: 192.168.1.100:80:inbound)
##   IP:PORT (mặc định inbound)
##   IP:DIRECTION (ví dụ: 192.168.1.100:outbound)
##   IP (block toàn bộ IP, mặc định inbound)
## Direction: inbound hoặc outbound

param(
    [Parameter(Position=0)]
    [string]$Param1 = "",
    
    [Parameter(Position=1)]
    [string]$Param2 = ""
)
echo "Firewall drop action started"
# ===============================
# Check Administrator
# ===============================
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    
    $errorResult = @{
        status = "error"
        data = @{
            message = "Administrator privileges required"
        }
    } | ConvertTo-Json
    
    Write-Output $errorResult
    exit 1
}

# ===============================
# Parse parameters
# ===============================
$Action = "add"
$InputFile = ""

# Kiểm tra nếu tham số đầu tiên là reset
if ($Param1 -eq "reset" -or $Param1 -eq "--reset") {
    $Action = "reset"
} else {
    $InputFile = if ($Param1) { $Param1 } else { "FirewallDrop.txt" }
    if ($Param2) {
        $Action = $Param2
    }
}

$RuleName = "LS_BLACKLIST"

# Nếu không phải path đầy đủ → mặc định trong C:\Program Files (x86)\LancsITIM\var\
if ($InputFile -and -not [System.IO.Path]::IsPathRooted($InputFile)) {
    $BlacklistFile = Join-Path "C:\Program Files (x86)\LancsITIM\var" $InputFile
} elseif ($InputFile) {
    $BlacklistFile = $InputFile
} else {
    $BlacklistFile = ""
}

# ===============================
# RESET: Xóa toàn bộ rules
# ===============================
if ($Action -eq "reset") {
    $status = "success"
    $errorMessage = ""
    
    try {
        # Xóa tất cả rules có DisplayName
        $existingRules = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
        if ($existingRules) {
            $existingRules | Remove-NetFirewallRule -ErrorAction Stop
        }
    } catch {
        $status = "error"
        $errorMessage = "Failed to remove firewall rules: $_"
    }
    
    if (-not $status) {
        $result = @{
            status = "error"
            data = @{
                action = "reset"
                chain = $RuleName
                message = $errorMessage
            }
        } | ConvertTo-Json -Compress
        
        Write-Output $result
        exit 1
    }
    
    $result = @{
        status = "success"
        data = @{
            action = "reset"
            chain = $RuleName
            message = "Chain $RuleName has been removed"
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $result
    exit 0
}

# ===============================
# ADD: Thêm rules
# ===============================

# Kiểm tra file tồn tại
if (-not $BlacklistFile -or -not (Test-Path $BlacklistFile)) {
    $errorResult = @{
        status = "error"
        data = @{
            action = "add"
            message = "Blacklist file not found: $BlacklistFile"
            blacklist_file = $BlacklistFile
            chain = $RuleName
            ip_count = 0
            ip_with_port_count = 0
            skipped_count = 0
            rules = @()
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}

# Kiểm tra file có rỗng không
$fileContent = Get-Content $BlacklistFile -ErrorAction SilentlyContinue
if (-not $fileContent -or $fileContent.Count -eq 0) {
    $errorResult = @{
        status = "error"
        data = @{
            action = "add"
            message = "Blacklist file is empty: $BlacklistFile"
            blacklist_file = $BlacklistFile
            chain = $RuleName
            ip_count = 0
            ip_with_port_count = 0
            skipped_count = 0
            rules = @()
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $errorResult
    exit 1
}

# Xóa rules cũ
try {
    $existingRules = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
    if ($existingRules) {
        $existingRules | Remove-NetFirewallRule -ErrorAction Stop
    }
} catch {
    # Continue even if removal fails
}

# Biến để lưu kết quả
$status = "success"
$errorMessage = ""
$ipCount = 0
$ipWithPortCount = 0
$skippedCount = 0
$rules = @()

# Đọc và xử lý từng dòng
try {
    $inputContent = Get-Content $BlacklistFile -ErrorAction Stop
    
    foreach ($line in $inputContent) {
        # Skip empty lines and comments
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            $skippedCount++
            continue
        }
        
        # Parse format: IP:PORT:DIRECTION hoặc IP:PORT hoặc IP:DIRECTION hoặc IP
        # Pattern để match IP (IPv4 hoặc IPv6 với CIDR)
        $ipPattern = '^((?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:/[0-9]{1,2})?|(?:[0-9a-fA-F:]+)(?:/[0-9]{1,3})?)(?::(.+))?$'
        
        if ($line -match $ipPattern) {
            $ip = $matches[1]
            $rest = $matches[2]
            
            $portInfo = ""
            $direction = "inbound"
            
            if ($rest) {
                # Parse PORT:DIRECTION hoặc PORT hoặc DIRECTION
                $parts = $rest -split ':', 2
                
                # Kiểm tra nếu phần đầu tiên là direction (inbound/outbound) thay vì port
                if ($parts[0] -match '^(inbound|outbound)$') {
                    # Trường hợp IP:DIRECTION (không có port)
                    $direction = $parts[0].ToLower()
                } elseif ($parts[0] -match '^\d+$' -or $parts[0] -match '^\d+-\d+$') {
                    # Trường hợp IP:PORT hoặc IP:PORT:DIRECTION
                    $portInfo = $parts[0]
                    if ($parts.Count -ge 2 -and $parts[1]) {
                        $direction = $parts[1].ToLower()
                    }
                } else {
                    # Không hợp lệ
                    $skippedCount++
                    continue
                }
            }
            
            # Validate direction
            if ($direction -ne "inbound" -and $direction -ne "outbound") {
                $direction = "inbound"
            }
            
            $ruleDesc = $line
            
            try {
                if ($portInfo) {
                    # Có port - xử lý port range hoặc single port
                    if ($portInfo -match '^(\d+)-(\d+)$') {
                        # Port range
                        $portStart = [int]$matches[1]
                        $portEnd = [int]$matches[2]
                        
                        # Tạo rule cho TCP và UDP
                        $fwDirection = if ($direction -eq "outbound") { "Outbound" } else { "Inbound" }
                        
                        New-NetFirewallRule `
                            -DisplayName "$RuleName" `
                            -Direction $fwDirection `
                            -Action Block `
                            -RemoteAddress $ip `
                            -Protocol TCP `
                            -LocalPort "$portStart-$portEnd" `
                            -Profile Any `
                            -ErrorAction Stop | Out-Null
                        
                        New-NetFirewallRule `
                            -DisplayName "$RuleName" `
                            -Direction $fwDirection `
                            -Action Block `
                            -RemoteAddress $ip `
                            -Protocol UDP `
                            -LocalPort "$portStart-$portEnd" `
                            -Profile Any `
                            -ErrorAction Stop | Out-Null
                        
                        $ipWithPortCount++
                        $rules += $ruleDesc
                    } elseif ($portInfo -match '^\d+$') {
                        # Single port
                        $port = [int]$portInfo
                        $fwDirection = if ($direction -eq "outbound") { "Outbound" } else { "Inbound" }
                        
                        New-NetFirewallRule `
                            -DisplayName "$RuleName" `
                            -Direction $fwDirection `
                            -Action Block `
                            -RemoteAddress $ip `
                            -Protocol TCP `
                            -LocalPort $port `
                            -Profile Any `
                            -ErrorAction Stop | Out-Null
                        
                        New-NetFirewallRule `
                            -DisplayName "$RuleName" `
                            -Direction $fwDirection `
                            -Action Block `
                            -RemoteAddress $ip `
                            -Protocol UDP `
                            -LocalPort $port `
                            -Profile Any `
                            -ErrorAction Stop | Out-Null
                        
                        $ipWithPortCount++
                        $rules += $ruleDesc
                    } else {
                        # Port không hợp lệ
                        $skippedCount++
                    }
                } else {
                    # Chỉ IP (có thể có direction), không có port - block toàn bộ traffic
                    $fwDirection = if ($direction -eq "outbound") { "Outbound" } else { "Inbound" }
                    
                    New-NetFirewallRule `
                        -DisplayName "$RuleName" `
                        -Direction $fwDirection `
                        -Action Block `
                        -RemoteAddress $ip `
                        -Profile Any `
                        -ErrorAction Stop | Out-Null
                    
                    $ipCount++
                    $rules += $ruleDesc
                }
            } catch {
                $status = "error"
                $errorMessage = "Failed to add rule for: $ruleDesc - $_"
                break
            }
        } else {
            $skippedCount++
        }
    }
} catch {
    $status = "error"
    $errorMessage = "Error reading blacklist file: $_"
}

# ===============================
# Return JSON result
# ===============================
if (-not $status) {
    $result = @{
        status = "error"
        data = @{
            # action = "add"
            # message = $errorMessage
            # blacklist_file = $BlacklistFile
            # chain = $RuleName
            # ip_count = $ipCount
            # ip_with_port_count = $ipWithPortCount
            # skipped_count = $skippedCount
            rules = $rules
        }
    } | ConvertTo-Json -Compress
    
    Write-Output $result
    exit 1
}

$result = @{
    status = "success"
    data = @{
        # action = "add"
        # blacklist_file = $BlacklistFile
        # chain = $RuleName
        # ip_count = $ipCount
        # ip_with_port_count = $ipWithPortCount
        # skipped_count = $skippedCount
        rules = $rules
        # message = "Applied blacklist from $BlacklistFile"
    }
} | ConvertTo-Json -Compress

Write-Output $result
