#!/bin/bash

# 1. Cấu hình biến
SERVICE_NAME=$1
echo "Restarting service: $SERVICE_NAME"
# 2. Kiểm tra quyền Root
if [[ $EUID -ne 0 ]]; then
   echo '{"status": "error", "message": "Must run as root"}'
   exit 1
fi

# 3. Kiểm tra tham số đầu vào
if [[ -z "$SERVICE_NAME" ]]; then
    echo '{"status": "error", "message": "Service name is required"}'
    exit 1
fi

# 4. Kiểm tra service có tồn tại không
if ! systemctl list-unit-files --type=service | grep -q "^${SERVICE_NAME}\.service"; then
    echo '{"status": "error", "service": "'$SERVICE_NAME'", "message": "Service not found"}'
    exit 1
fi

# 5. Thực hiện Restart
# Dùng --no-block để linh hoạt hoặc bỏ qua nếu muốn đợi đồng bộ
if systemctl restart "$SERVICE_NAME" 2>/dev/null; then
    FINAL_STATUS=$(systemctl is-active "$SERVICE_NAME")
    # Trả về JSON một dòng duy nhất, không cần dấu \ rối rắm
    echo '{"status": "success", "service": "'$SERVICE_NAME'", "final_status": "'$FINAL_STATUS'"}'
    exit 0
else
    FINAL_STATUS=$(systemctl is-active "$SERVICE_NAME")
    echo '{"status": "error", "service": "'$SERVICE_NAME'", "final_status": "'$FINAL_STATUS'", "message": "Restart failed"}'
    exit 1
fi
