#!/bin/bash
# Script thu thập thông tin BIOS trên Linux

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin BIOS
bios_output=$(dmidecode -t bios 2>/dev/null || echo "dmidecode command not available")

# Parse BIOS information
bios_info="{}"
if [ -n "$bios_output" ] && [[ "$bios_output" != *"not available"* ]]; then
    bios_info="{"
    first=true

    # Extract key BIOS information
    manufacturer=$(echo "$bios_output" | grep -i "Vendor:" | head -1 | sed 's/.*: //' | sed 's/"/\\"/g' || echo "")
    version=$(echo "$bios_output" | grep -i "Version:" | head -1 | sed 's/.*: //' | sed 's/"/\\"/g' || echo "")
    release_date=$(echo "$bios_output" | grep -i "Release Date:" | head -1 | sed 's/.*: //' | sed 's/"/\\"/g' || echo "")
    rom_size=$(echo "$bios_output" | grep -i "ROM Size:" | head -1 | sed 's/.*: //' | sed 's/"/\\"/g' || echo "")
    characteristics=$(echo "$bios_output" | grep -i "Characteristics:" | head -1 | sed 's/.*: //' | sed 's/"/\\"/g' || echo "")

    bios_info="${bios_info}\"manufacturer\":\"${manufacturer}\",\"version\":\"${version}\",\"release_date\":\"${release_date}\",\"rom_size\":\"${rom_size}\",\"characteristics\":\"${characteristics}\""
    
    bios_info="${bios_info}}"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"bios\":${bios_info}}}"

# Xuất JSON kết quả
echo "$result"