#!/bin/bash
# Script thu thập thông tin phiên đăng nhập người dùng Linux
# Sử dụng các lệnh: who -u, w, last -n 50

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin phiên đăng nhập từ loginctl nếu có
loginctl_output=$(loginctl list-sessions --no-legend 2>/dev/null || echo "")

# Parse user sessions từ loginctl
sessions="[]"
if [ -n "$loginctl_output" ]; then
    sessions="["$(
        echo "$loginctl_output" | awk '
        {
            session_id = $1
            user = $2
            seat = $3
            # Get session info
            cmd = "loginctl show-session " session_id " 2>/dev/null"
            while ((cmd | getline line) > 0) {
                if (line ~ /^TTY=/) {
                    tty = substr(line, 5)
                } else if (line ~ /^Remote=/) {
                    remote = substr(line, 8)
                } else if (line ~ /^State=/) {
                    state = substr(line, 7)
                } else if (line ~ /^Type=/) {
                    type = substr(line, 6)
                }
            }
            close(cmd)
            printf "{\"username\":\"%s\",\"session_name\":\"%s\",\"id\":\"%s\",\"state\":\"%s\",\"type\":\"%s\",\"device\":\"%s\",\"from\":\"%s\",\"login_time\":\"Unknown\",\"idle_time\":\"\"},", user, session_id, session_id, state, type, tty, remote
        }
        ' | sed 's/,$//'
    )"]"
fi

# Tạo JSON kết quả
result=$(cat <<EOF
{
  "status": "success",
  "data": {
    "hostname": "${hostname}",
    "timestamp": "${timestamp}",
    "sessions": ${sessions}
  }
}
EOF
)

# Xuất JSON kết quả
echo "$result"