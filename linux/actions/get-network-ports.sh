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
    
    echo "$ss_output" | while IFS= read -r line; do
        # Skip header line
        if [[ $line == State* ]] || [[ $line == *Local* ]]; then
            continue
        fi
        
        # Parse line: State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
        if [[ $line =~ ^LISTEN ]]; then
            # Extract protocol, local address and port
            protocol=""
            local_addr=""
            local_port=""
            
            # Check if TCP or UDP
            if [[ $line == tcp* ]]; then
                protocol="TCP"
            elif [[ $line == udp* ]]; then
                protocol="UDP"
            fi
            
            # Extract local address:port
            if [[ $line =~ ([0-9a-fA-F:.]+):([0-9]+) ]]; then
                local_addr="${BASH_REMATCH[1]}"
                local_port="${BASH_REMATCH[2]}"
            fi
            
            if [ -n "$protocol" ] && [ -n "$local_port" ]; then
                if [ "$first" = true ]; then
                    first=false
                else
                    network_ports="${network_ports},"
                fi
                
                network_ports="${network_ports}{\"protocol\":\"${protocol}\",\"local_address\":\"${local_addr}\",\"local_port\":${local_port},\"state\":\"LISTENING\"}"
            fi
        fi
    done
    
    network_ports="${network_ports}]"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"network_ports\":${network_ports}}}"

# Xuất JSON kết quả
echo "$result"