#!/bin/bash
# Script thu thập thông tin Controllers trên Linux

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin PCI controllers
pci_output=$(lspci -v 2>/dev/null | grep -E "(controller|Controller|CONTROLLER)" || echo "")

# Lấy thông tin USB controllers
usb_output=$(lsusb 2>/dev/null || echo "")

# Parse controllers
controllers="[]"
if [ -n "$pci_output" ] || [ -n "$usb_output" ]; then
    controllers="["
    first=true

    # Parse PCI controllers
    if [ -n "$pci_output" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                # Extract PCI bus info and device name
                bus_info=$(echo "$line" | cut -d' ' -f1)
                device_name=$(echo "$line" | cut -d':' -f3- | sed 's/^ *//')

                if [ "$first" = true ]; then
                    first=false
                else
                    controllers="${controllers},"
                fi

                controllers="${controllers}{\"type\":\"PCI\",\"bus_info\":\"${bus_info}\",\"name\":\"${device_name}\",\"description\":\"PCI Controller\"}"
            fi
        done <<< "$pci_output"
    fi

    # Parse USB controllers
    if [ -n "$usb_output" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ] && [[ $line == Bus* ]]; then
                # Extract USB bus and device info
                bus=$(echo "$line" | awk '{print $2}' | tr -d ':')
                device=$(echo "$line" | awk '{print $4}' | tr -d ':')
                usb_name=$(echo "$line" | cut -d' ' -f7-)

                if [ "$first" = true ]; then
                    first=false
                else
                    controllers="${controllers},"
                fi

                controllers="${controllers}{\"type\":\"USB\",\"bus\":\"${bus}\",\"device\":\"${device}\",\"name\":\"${usb_name}\",\"description\":\"USB Controller\"}"
            fi
        done <<< "$usb_output"
    fi

    controllers="${controllers}]"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"controllers\":${controllers}}}"

# Xuất JSON kết quả
echo "$result"