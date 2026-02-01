#!/bin/bash
# Script thu thập thông tin bảng định tuyến Linux
# Sử dụng các lệnh: ip route show, netstat -rn

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

# Lấy thông tin bảng định tuyến
ip_route_output=$(ip route show)
netstat_output=$(netstat -rn)

# Tạo JSON kết quả
ip_route_escaped=$(echo "$ip_route_output" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')
netstat_escaped=$(echo "$netstat_output" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')

result=$(cat <<EOF
{
  "status": "success",
  "data": {
    "hostname": "${hostname}",
    "timestamp": "${timestamp}",
    "routing_table": {
      "route": "$ip_route_escaped",
      "net_route": "$netstat_escaped"
    }
  }
}
EOF
)

# Xuất JSON kết quả
echo "$result"