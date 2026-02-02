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
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    ram_output=$(sudo dmidecode -t memory 2>/dev/null | grep -A 20 "Memory Device" || echo "")
else
    ram_output=$(dmidecode -t memory 2>/dev/null | grep -A 20 "Memory Device" || echo "")
fi

# Lấy thông tin memory usage từ free
free_output=$(free -h 2>/dev/null || echo "")

# Parse RAM modules
ram_modules="[]"
if [ -n "$ram_output" ]; then
    ram_modules="["$(
        LC_NUMERIC=C awk '
        BEGIN { count = 0 }
        /Memory Device/ {
            bank_label = ""
            capacity_gb = 0
            manufacturer = ""
            part_number = ""
            speed_mhz = 0
            memory_type = ""
            form_factor = ""
            serial_number = ""
        }
        /Size:/ {
            size = $0
            sub(/.*Size: /, "", size)
            if (size ~ /MB/) {
                sub(/ MB/, "", size)
                capacity_gb = size / 1024
            } else if (size ~ /GB/) {
                sub(/ GB/, "", size)
                capacity_gb = size
            }
        }
        /Locator:/ {
            sub(/.*Locator: /, "", bank_label)
            gsub(/"/, "\\\"", bank_label)
        }
        /Manufacturer:/ {
            sub(/.*Manufacturer: /, "", manufacturer)
            gsub(/"/, "\\\"", manufacturer)
        }
        /Part Number:/ {
            sub(/.*Part Number: /, "", part_number)
            gsub(/"/, "\\\"", part_number)
        }
        /Speed:/ {
            sub(/.*Speed: /, "", speed_mhz)
            sub(/ MHz/, "", speed_mhz)
        }
        /Type:/ {
            sub(/.*Type: /, "", memory_type)
        }
        /Form Factor:/ {
            sub(/.*Form Factor: /, "", form_factor)
        }
        /Serial Number:/ {
            sub(/.*Serial Number: /, "", serial_number)
            if (capacity_gb > 0) {
                modules[count++] = sprintf("{\"bank_label\":\"%s\",\"capacity_gb\":%.2f,\"manufacturer\":\"%s\",\"part_number\":\"%s\",\"speed_mhz\":%s,\"memory_type\":\"%s\",\"form_factor\":\"%s\",\"serial_number\":\"%s\"}", bank_label, capacity_gb, manufacturer, part_number, speed_mhz, memory_type, form_factor, serial_number)
            }
        }
        END {
            for (i = 0; i < count; i++) {
                if (i > 0) printf ","
                printf "%s", modules[i]
            }
        }
        ' <<< "$ram_output"
    )"]"
fi

# Parse memory usage
memory_usage="{}"
if [ -n "$free_output" ]; then
    # Get memory in bytes
    free_bytes_output=$(free -b 2>/dev/null || echo "")
    if [ -n "$free_bytes_output" ]; then
        total_bytes=$(echo "$free_bytes_output" | grep "^Mem:" | awk '{print $2}' || echo "0")
        used_bytes=$(echo "$free_bytes_output" | grep "^Mem:" | awk '{print $3}' || echo "0")
        free_bytes=$(echo "$free_bytes_output" | grep "^Mem:" | awk '{print $4}' || echo "0")

        # Convert to GB
        total_gb=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", $total_bytes / 1024 / 1024 / 1024}")
        used_gb=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", $used_bytes / 1024 / 1024 / 1024}")
        free_gb=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", $free_bytes / 1024 / 1024 / 1024}")

        # Calculate percent
        if [ "$total_bytes" -gt 0 ]; then
            percent=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", ($used_bytes / $total_bytes) * 100}")
        else
            percent="0.00"
        fi

        memory_usage="{\"total_physical_memory_gb\":${total_gb},\"free_physical_memory_gb\":${free_gb},\"used_physical_memory_gb\":${used_gb},\"memory_usage_percent\":${percent}}"
    fi
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"ram\":{\"modules\":${ram_modules},\"usage\":${memory_usage}}}}"

# Xuất JSON kết quả
echo "$result" 2>/dev/null || true