#!/bin/bash
# Script thu thập thông tin Storage trên Linux

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin block devices từ lsblk
lsblk_output=$(lsblk -n -o NAME,MODEL,SIZE,SERIAL,ROTA,TYPE 2>/dev/null || echo "")

# Lấy thông tin filesystem usage từ df
df_output=$(df -h 2>/dev/null | grep -E "^/dev/" || echo "")

# Parse physical disks từ lsblk
physical_disks="[]"
if [ -n "$lsblk_output" ]; then
    physical_disks="["$(
        echo "$lsblk_output" | awk '
        $6 == "disk" {
            name = $1
            model = $2
            size = $3
            serial = $4
            rota = $5
            type = $6
            printf "{\"name\":\"%s\",\"model\":\"%s\",\"size\":\"%s\",\"serial\":\"%s\",\"rota\":\"%s\",\"type\":\"%s\"},", name, model, size, serial, rota, type
        }
        ' | sed 's/,$//'
    )"]"
fi

# Parse logical disks từ df
logical_disks="[]"
if [ -n "$df_output" ]; then
    logical_disks="["$(
        echo "$df_output" | awk '
        {
            device = $1
            size = $2
            used = $3
            avail = $4
            use_percent = $5
            mountpoint = $6
            printf "{\"device\":\"%s\",\"mountpoint\":\"%s\",\"size\":\"%s\",\"used\":\"%s\",\"avail\":\"%s\",\"use_percent\":\"%s\"},", device, mountpoint, size, used, avail, use_percent
        }
        ' | sed 's/,$//'
    )"]"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"storage\":{\"physical_disks\":${physical_disks},\"logical_disks\":${logical_disks}}}}"

# Xuất JSON kết quả
echo "$result"