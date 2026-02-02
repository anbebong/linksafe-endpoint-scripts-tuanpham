#!/bin/bash
# Script thu thập thông tin các port mạng đang listening trên Linux
# Sử dụng các lệnh: ss -tulpn, netstat -tulpn

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin port listening
ss_output=$(ss -tulpn 2>/dev/null | grep LISTEN || echo "")

# Parse ss output
network_ports="[]"
if [ -n "$ss_output" ]; then
    network_ports="["
    first=true
    
    while IFS= read -r entry; do
        if [ "$first" = true ]; then
            first=false
        else
            network_ports="${network_ports},"
        fi
        network_ports="${network_ports}${entry}"
    done < <(echo "$ss_output" | awk '
    NR > 1 && $2 == "LISTEN" {
        protocol = toupper($1)
        split($5, addr_port, ":")
        local_addr = addr_port[1]
        for (i=2; i<length(addr_port); i++) {
            if (i > 2) local_addr = local_addr ":"
            local_addr = local_addr addr_port[i]
        }
        local_port = addr_port[length(addr_port)]
        if (protocol && local_port) {
            printf "{\"protocol\":\"%s\",\"local_address\":\"%s\",\"local_port\":%d,\"state\":\"LISTENING\"}\n", protocol, local_addr, local_port
        }
    }
    ')
    
    network_ports="${network_ports}]"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"network_ports\":${network_ports}}}"

# Xuất JSON kết quả
echo "$result"