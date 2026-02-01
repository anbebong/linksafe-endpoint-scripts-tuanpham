#Requires -Version 5.1
echo "Logout action started"
try {
    # 1. Lấy danh sách session ID
    $quserOutput = quser 2>$null
    if (-not $quserOutput) { throw "No active sessions found" }
    
    $sessionIds = $quserOutput -split "`n" | ForEach-Object {
        if ($_ -match "(\d+)\s+(Active|Disc)") { $matches[1] }
    }

    if (-not $sessionIds) { throw "No sessions to disconnect" }

    # 2. Thực hiện disconnect
    $failedCount = 0
    foreach ($id in $sessionIds) {
        $proc = Start-Process "tsdiscon.exe" -ArgumentList $id -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
        if ($proc.ExitCode -ne 0) { $failedCount++ }
    }

    # 3. FIX TRIỆT ĐỂ: Tách riêng logic gán biến
    $finalStatus = "success"
    $finalMessage = "Disconnected all sessions"

    if ($failedCount -gt 0) {
        $finalStatus = "error"
        $finalMessage = "Failed to disconnect $failedCount session(s)"
    }

    $result = @{
        status   = $finalStatus
        hostname = $env:COMPUTERNAME
        message  = $finalMessage
    }
    
    # Xuất JSON sạch
    $result | ConvertTo-Json -Compress | Write-Output
    
    # Thoát với Exit Code chuẩn
    if ($failedCount -eq 0) { exit 0 } else { exit 1 }

} catch {
    $result = @{
        status   = "error"
        hostname = $env:COMPUTERNAME
        message  = $_.Exception.Message
    }
    $result | ConvertTo-Json -Compress | Write-Output
    exit 1
}