#!/bin/bash
# Script thu thập thông tin hệ thống tệp tin Linux
# Sử dụng lệnh: df -h --output=source,fstype,size,used,avail,pcent,target

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"
source "${BASE_DIR}/lib/os-detect.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin hệ thống tệp tin
filesystem_output=$(df -h --output=source,fstype,size,used,avail,pcent,target)

# Tạo JSON kết quả
filesystem_escaped=$(echo "$filesystem_output" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')

result=$(cat <<EOF
{
  "status": "success",
  "data": {
    "hostname": "${hostname}",
    "timestamp": "${timestamp}",
    "filesystems": "$filesystem_escaped"
  }
}
EOF
)

# Xuất JSON kết quả
echo "$result"