#!/bin/bash
# Script thu thập thông tin Sound/Audio trên Linux

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin sound cards từ /proc/asound/cards
cards_output=$(cat /proc/asound/cards 2>/dev/null || echo "")

# Lấy thông tin ALSA devices từ aplay
aplay_output=$(aplay -l 2>/dev/null || echo "")

# Parse sound devices
sound_devices="[]"
device_list=""

# Parse từ /proc/asound/cards
if [ -n "$cards_output" ]; then
    while IFS= read -r line; do
        # Parse lines like: " 0 [PCH            ]: HDA-Intel - HDA Intel PCH"
        if [[ $line =~ ^\s*[0-9]+\s*\[([^\]]+)\]\s*:\s*(.+)$ ]]; then
            card_id=$(echo "$line" | sed 's/^\s*\([0-9]\+\).*/\1/')
            card_short_name="${BASH_REMATCH[1]}"
            card_description="${BASH_REMATCH[2]}"

            if [ -n "$device_list" ]; then
                device_list="${device_list},"
            fi
            device_list="${device_list}{\"name\":\"${card_description}\",\"device_id\":\"${card_id}\",\"manufacturer\":\"Unknown\",\"product_name\":\"${card_short_name}\",\"status\":\"Unknown\",\"status_info\":\"\",\"pnp_device_id\":\"\",\"hardware_id\":\"\",\"driver_provider_name\":\"\",\"driver_version\":\"\",\"driver_date\":\"\"}"
        fi
    done <<< "$cards_output"
fi

# Parse từ aplay -l để bổ sung thông tin
if [ -n "$aplay_output" ]; then
    while IFS= read -r line; do
        # Parse lines like: "card 0: PCH [HDA Intel PCH], device 0: ALC295 Analog [ALC295 Analog]"
        if [[ $line == card* ]]; then
            card_num=$(echo "$line" | sed 's/card \([0-9]\+\):.*/\1/')
            card_name=$(echo "$line" | sed 's/.*: \([^,]*\),.*/\1/')
            device_num=$(echo "$line" | sed 's/.*device \([0-9]\+\):.*/\1/')
            device_name=$(echo "$line" | sed 's/.*device [0-9]\+: \(.*\)$/\1/')

            if [ -n "$device_list" ]; then
                device_list="${device_list},"
            fi
            device_list="${device_list}{\"name\":\"${device_name}\",\"device_id\":\"${card_num}:${device_num}\",\"manufacturer\":\"Unknown\",\"product_name\":\"${card_name}\",\"status\":\"Unknown\",\"status_info\":\"\",\"pnp_device_id\":\"\",\"hardware_id\":\"\",\"driver_provider_name\":\"\",\"driver_version\":\"\",\"driver_date\":\"\"}"
        fi
    done <<< "$aplay_output"
fi

if [ -n "$device_list" ]; then
    sound_devices="[${device_list}]"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"sound_audio\":${sound_devices}}}"

# Xuất JSON kết quả
echo "$result"