#!/bin/bash
# Script thu thập thông tin hệ điều hành Linux
# Sử dụng các lệnh: cat /etc/os-release, lsb_release -a, uname -a

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"
source "${BASE_DIR}/lib/os-detect.sh"

# Thu thập thông tin hệ điều hành
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin OS release
os_release=$(cat /etc/os-release 2>/dev/null || echo "Không khả dụng")
lsb_release_output=$(lsb_release -a 2>/dev/null || echo "lsb_release không khả dụng")
uname_output=$(uname -a)

# Phân tích thông tin từ os-release
os_name=$(echo "$os_release" | grep "^NAME=" | cut -d'=' -f2 | sed 's/"//g' || echo "Unknown")
os_version=$(echo "$os_release" | grep "^VERSION=" | cut -d'=' -f2 | sed 's/"//g' || echo "Unknown")
os_manufacturer="Linux"

# Phân tích từ uname
kernel_info=$(uname -a)
architecture=$(uname -m)
kernel_version=$(uname -r)

# Tạo JSON kết quả
result=$(cat <<EOF
{
  "status": "success",
  "data": {
    "hostname": "${hostname}",
    "timestamp": "${timestamp}",
    "os_info": {
      "os_name": "$os_name",
      "os_version": "$os_version",
      "os_manufacturer": "$os_manufacturer",
      "architecture": "$architecture",
      "kernel_version": "$kernel_version",
      "os_release": "$os_release",
      "lsb_release": "$lsb_release_output",
      "uname": "$uname_output"
    }
  }
}
EOF
)

# Xuất JSON kết quả
echo "$result"