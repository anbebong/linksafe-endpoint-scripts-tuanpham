#!/bin/bash
# Script thu thập thông tin RAM trên Linux

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin RAM modules từ dmidecode
ram_output=$(dmidecode -t memory 2>/dev/null | grep -A 20 "Memory Device" || echo "")

# Lấy thông tin memory usage từ free
free_output=$(free -h 2>/dev/null || echo "")

# Parse RAM modules
ram_modules="[]"
if [ -n "$ram_output" ]; then
    ram_modules="["
    first=true

    # Parse each memory device
    echo "$ram_output" | while IFS= read -r line; do
        if [[ $line == *"Memory Device"* ]]; then
            # Start of new memory device
            if [ "$first" = true ]; then
                first=false
            else
                ram_modules="${ram_modules},"
            fi

            # Read next lines for device info
            device_info=""
            for i in {1..15}; do
                read -r next_line
                if [ -n "$next_line" ] && [[ $next_line == *":"* ]]; then
                    device_info="${device_info}${next_line};"
                fi
            done

            # Extract key information
            size=$(echo "$device_info" | grep -o "Size: [^;]*" | sed 's/Size: //' | sed 's/"/\\"/g' || echo "")
            locator=$(echo "$device_info" | grep -o "Locator: [^;]*" | sed 's/Locator: //' | sed 's/"/\\"/g' || echo "")
            manufacturer=$(echo "$device_info" | grep -o "Manufacturer: [^;]*" | sed 's/Manufacturer: //' | sed 's/"/\\"/g' || echo "")
            part_number=$(echo "$device_info" | grep -o "Part Number: [^;]*" | sed 's/Part Number: //' | sed 's/"/\\"/g' || echo "")
            speed=$(echo "$device_info" | grep -o "Speed: [^;]*" | sed 's/Speed: //' | sed 's/"/\\"/g' || echo "")

            ram_modules="${ram_modules}{\"size\":\"${size}\",\"locator\":\"${locator}\",\"manufacturer\":\"${manufacturer}\",\"part_number\":\"${part_number}\",\"speed\":\"${speed}\"}"
        fi
    done <<< "$ram_output"

    ram_modules="${ram_modules}]"
fi

# Parse memory usage
memory_usage="{}"
if [ -n "$free_output" ]; then
    # Extract memory info from free -h output
    total=$(echo "$free_output" | grep "^Mem:" | awk '{print $2}' || echo "")
    used=$(echo "$free_output" | grep "^Mem:" | awk '{print $3}' || echo "")
    free=$(echo "$free_output" | grep "^Mem:" | awk '{print $4}' || echo "")

    memory_usage="{\"total\":\"${total}\",\"used\":\"${used}\",\"free\":\"${free}\"}"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"ram\":{\"modules\":${ram_modules},\"usage\":${memory_usage}}}}"

# Xuất JSON kết quả
echo "$result"