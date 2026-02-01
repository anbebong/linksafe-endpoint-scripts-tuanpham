#!/bin/bash
# Script thu thập thông tin phần cứng Linux
# Sử dụng các lệnh: lshw -json, dmidecode

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Parse thông tin từ lshw (JSON format)
computer_system_name="Unknown"
computer_system_manufacturer="Unknown"
computer_system_model="Unknown"
total_physical_memory="Unknown"
number_of_processors="Unknown"
number_of_logical_processors="Unknown"

if command -v lshw >/dev/null 2>&1; then
    lshw_json=$(lshw -json 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$lshw_json" ]; then
        # Parse computer system info
        computer_system_name=$(echo "$lshw_json" | grep -o '"id":"core"[^}]*' | grep -o '"product":"[^"]*"' | head -1 | sed 's/"product":"//;s/"//')
        computer_system_manufacturer=$(echo "$lshw_json" | grep -o '"id":"core"[^}]*' | grep -o '"vendor":"[^"]*"' | head -1 | sed 's/"vendor":"//;s/"//')
        computer_system_model=$(echo "$lshw_json" | grep -o '"id":"core"[^}]*' | grep -o '"product":"[^"]*"' | head -1 | sed 's/"product":"//;s/"//')

        # Parse memory
        total_physical_memory=$(echo "$lshw_json" | grep -o '"id":"memory"[^}]*' | grep -o '"size":[0-9]*' | head -1 | sed 's/"size"://')

        # Parse CPU
        number_of_processors=$(echo "$lshw_json" | grep -o '"class":"processor"[^}]*' | wc -l)
        number_of_logical_processors=$(echo "$lshw_json" | grep -o '"class":"processor"[^}]*' | grep -o '"configuration":{"cores":[0-9]*' | sed 's/.*"cores":\([0-9]*\).*/\1/' | awk '{sum+=$1} END {print sum}')
    fi
fi

# Parse thông tin từ dmidecode cho base board
base_board_manufacturer="Unknown"
base_board_product="Unknown"
base_board_version="Unknown"
base_board_serial="Unknown"

if command -v dmidecode >/dev/null 2>&1; then
    dmidecode_output=$(dmidecode -t baseboard 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$dmidecode_output" ]; then
        base_board_manufacturer=$(echo "$dmidecode_output" | grep "Manufacturer:" | head -1 | sed 's/.*Manufacturer:\s*//')
        base_board_product=$(echo "$dmidecode_output" | grep "Product Name:" | head -1 | sed 's/.*Product Name:\s*//')
        base_board_version=$(echo "$dmidecode_output" | grep "Version:" | head -1 | sed 's/.*Version:\s*//')
        base_board_serial=$(echo "$dmidecode_output" | grep "Serial Number:" | head -1 | sed 's/.*Serial Number:\s*//')
    fi
fi

# Tạo JSON kết quả
result=$(cat <<EOF
{
  "status": "success",
  "data": {
    "hostname": "${hostname}",
    "timestamp": "${timestamp}",
    "hardware": {
      "computer_system": {
        "name": "${computer_system_name}",
        "manufacturer": "${computer_system_manufacturer}",
        "model": "${computer_system_model}",
        "total_physical_memory": "${total_physical_memory}",
        "number_of_processors": "${number_of_processors}",
        "number_of_logical_processors": "${number_of_logical_processors}"
      },
      "base_board": {
        "manufacturer": "${base_board_manufacturer}",
        "product": "${base_board_product}",
        "version": "${base_board_version}",
        "serial_number": "${base_board_serial}"
      }
    }
  }
}
EOF
)

# Xuất JSON kết quả
echo "$result"