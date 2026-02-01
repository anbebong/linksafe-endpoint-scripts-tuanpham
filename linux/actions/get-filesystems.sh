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

# Parse filesystem information
filesystems="[]"
if [ -n "$filesystem_output" ]; then
    filesystems="["
    first=true

    echo "$filesystem_output" | tail -n +2 | while IFS= read -r line; do
        # Parse df output: Filesystem Type Size Used Avail Use% Mounted
        if [[ $line =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
            device="${BASH_REMATCH[1]}"
            fstype="${BASH_REMATCH[2]}"
            size="${BASH_REMATCH[3]}"
            used="${BASH_REMATCH[4]}"
            avail="${BASH_REMATCH[5]}"
            usep="${BASH_REMATCH[6]}"
            mount="${BASH_REMATCH[7]}"

            if [ "$first" = true ]; then
                first=false
            else
                filesystems="${filesystems},"
            fi

            filesystems="${filesystems}{\"device_id\":\"${device}\",\"filesystem\":\"${fstype}\",\"size\":\"${size}\",\"free_space\":\"${avail}\",\"mount_point\":\"${mount}\",\"used\":\"${used}\",\"use_percent\":\"${usep}\"}"
        fi
    done

    filesystems="${filesystems}]"
fi

# Tạo JSON kết quả
result=$(cat <<EOF
{
  "status": "success",
  "data": {
    "hostname": "${hostname}",
    "timestamp": "${timestamp}",
    "filesystems": ${filesystems}
  }
}
EOF
)

# Xuất JSON kết quả
echo "$result"