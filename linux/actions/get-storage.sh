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
lsblk_output=$(lsblk -J 2>/dev/null || echo "{}")

# Lấy thông tin filesystem usage từ df
df_output=$(df -h 2>/dev/null | grep -E "^/dev/" || echo "")

# Parse physical disks từ lsblk JSON
physical_disks="[]"
logical_disks="[]"

if [ "$lsblk_output" != "{}" ] && [ -n "$lsblk_output" ]; then
    # Extract physical disks (type: disk)
    physical_disks=$(echo "$lsblk_output" | jq -c '[.blockdevices[] | select(.type == "disk") | {name: .name, model: .model, size: .size, serial: .serial, rota: .rota, type: .type}]' 2>/dev/null || echo "[]")

    # Extract logical disks (mountpoints)
    logical_disks=$(echo "$lsblk_output" | jq -c '[.blockdevices[] | select(.mountpoints != null) | .mountpoints[] as $mp | {device: .name, mountpoint: $mp, fstype: .fstype, size: .size, used: .used, avail: .avail}]' 2>/dev/null || echo "[]")
fi

# Fallback: parse df output if lsblk fails
if [ "$logical_disks" = "[]" ] && [ -n "$df_output" ]; then
    logical_disks="["
    first=true

    echo "$df_output" | while read -r line; do
        filesystem=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        avail=$(echo "$line" | awk '{print $4}')
        use_percent=$(echo "$line" | awk '{print $5}')
        mountpoint=$(echo "$line" | awk '{print $6}')

        if [ "$first" = true ]; then
            first=false
        else
            logical_disks="${logical_disks},"
        fi

        logical_disks="${logical_disks}{\"device\":\"${filesystem}\",\"mountpoint\":\"${mountpoint}\",\"size\":\"${size}\",\"used\":\"${used}\",\"avail\":\"${avail}\",\"use_percent\":\"${use_percent}\"}"
    done

    logical_disks="${logical_disks}]"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"storage\":{\"physical_disks\":${physical_disks},\"logical_disks\":${logical_disks}}}}"

# Xuất JSON kết quả
echo "$result"