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

# Lấy thông tin phiên đăng nhập
who_output=$(who -u 2>/dev/null || echo "who command not available")
w_output=$(w 2>/dev/null || echo "w command not available")
last_output=$(last -n 50 2>/dev/null || echo "last command not available")

# Parse user sessions từ w output
sessions="[]"
if [ -n "$w_output" ]; then
    sessions="["
    first=true

    # Skip header lines (first 2 lines)
    echo "$w_output" | tail -n +3 | while IFS= read -r line; do
        if [ -n "$line" ]; then
            # Parse w output: USER TTY FROM LOGIN@ IDLE JCPU PCPU WHAT
            user=$(echo "$line" | awk '{print $1}')
            tty=$(echo "$line" | awk '{print $2}')
            from=$(echo "$line" | awk '{print $3}')
            login_time=$(echo "$line" | awk '{print $4}')
            idle=$(echo "$line" | awk '{print $5}')
            jcpu=$(echo "$line" | awk '{print $6}')
            pcpu=$(echo "$line" | awk '{print $7}')
            what=$(echo "$line" | awk '{for(i=8;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')

            if [ "$first" = true ]; then
                first=false
            else
                sessions="${sessions},"
            fi

            sessions="${sessions}{\"username\":\"${user}\",\"session_name\":\"${tty}\",\"id\":\"\",\"state\":\"Active\",\"type\":\"\",\"device\":\"${tty}\",\"from\":\"${from}\",\"login_time\":\"${login_time}\",\"idle_time\":\"${idle}\"}"
        fi
    done

    sessions="${sessions}]"
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