#!/bin/bash
# Script thu thập thông tin biến môi trường trên Linux

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin biến môi trường
env_output=$(env 2>/dev/null || printenv 2>/dev/null || echo "")

# Parse environment variables
environment_variables="[]"
if [ -n "$env_output" ]; then
    environment_variables="["
    first=true

    while IFS='=' read -r name value; do
        if [ -n "$name" ]; then
            # Escape special characters in value
            value_escaped=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')

            if [ "$first" = true ]; then
                first=false
            else
                environment_variables="${environment_variables},"
            fi

            environment_variables="${environment_variables}{\"name\":\"${name}\",\"value\":\"${value_escaped}\"}"
        fi
    done <<< "$env_output"

    environment_variables="${environment_variables}]"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"environment_variables\":${environment_variables}}}"

# Xuất JSON kết quả
echo "$result"