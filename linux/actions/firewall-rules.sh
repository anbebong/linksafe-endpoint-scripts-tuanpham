#!/bin/bash

## Run Script: 
## firewall-rules.sh FirewallDrop.txt   # Thêm rules
## firewall-rules.sh reset           # Xóa toàn bộ chain
##
## Format file FirewallDrop.txt :
##   IP:PORT:DIRECTION (ví dụ: 192.168.1.100:80:inbound)
##   IP:PORT (mặc định inbound)
##   IP (block toàn bộ IP, mặc định inbound)
## Direction: inbound hoặc outbound

# Tham số đầu vào
# Kiểm tra nếu tham số đầu tiên là "reset" thì đó là ACTION
if [ "$1" = "reset" ]; then
    ACTION="reset"
    INPUT_FILE=""
else
    INPUT_FILE="${1:-FirewallDrop.txt}"
    ACTION="${2:-add}"  # add hoặc reset
fi

# Nếu là path tương đối → đặt trong /tmp
if [ -n "$INPUT_FILE" ] && [[ "$INPUT_FILE" != /* ]]; then
    BLACKLIST="/tmp/$INPUT_FILE"
elif [ -n "$INPUT_FILE" ]; then
    BLACKLIST="$INPUT_FILE"
else
    BLACKLIST=""
fi

CHAIN="LS_BLACKLIST"

# Biến để lưu kết quả
SUCCESS=true
ERROR_MESSAGE=""
IP_COUNT=0
IP_WITH_PORT_COUNT=0
SKIPPED_COUNT=0
RULES=()

# ===============================
# RESET: Xóa toàn bộ chain
# ===============================
if [ "$ACTION" = "reset" ]; then
    # Xóa chain khỏi INPUT và OUTPUT (redirect output để không hiển thị)
    iptables -D INPUT -j "$CHAIN" >/dev/null 2>&1
    iptables -D OUTPUT -j "$CHAIN" >/dev/null 2>&1
    
    # Flush và xóa chain
    iptables -F "$CHAIN" >/dev/null 2>&1
    iptables -X "$CHAIN" >/dev/null 2>&1
    
    # Save rules
    SAVE_SUCCESS=true
    SAVE_METHOD=""
    SAVE_WARNING=""
    
    if command -v netfilter-persistent >/dev/null 2>&1; then
        if netfilter-persistent save >/dev/null 2>&1; then
            SAVE_METHOD="netfilter-persistent"
        else
            SAVE_SUCCESS=false
            SAVE_WARNING="Failed to save with netfilter-persistent"
        fi
    elif command -v iptables-save >/dev/null 2>&1; then
        # Tạo thư mục nếu chưa tồn tại
        if [ ! -d "/etc/iptables" ]; then
            mkdir -p /etc/iptables >/dev/null 2>&1 || {
                SAVE_WARNING="Cannot create /etc/iptables directory, rules not persisted"
                SAVE_SUCCESS=false
            }
        fi
        
        if [ -d "/etc/iptables" ]; then
            if iptables-save > /etc/iptables/rules.v4 2>/dev/null; then
                SAVE_METHOD="iptables-save"
            else
                SAVE_SUCCESS=false
                SAVE_WARNING="Failed to save iptables rules"
            fi
        fi
    fi
    
    if [ "$SAVE_SUCCESS" = true ]; then
        echo "{\"success\":true,\"action\":\"reset\",\"chain\":\"$CHAIN\",\"message\":\"Chain $CHAIN has been removed\",\"save_method\":\"$SAVE_METHOD\"}"
    else
        echo "{\"success\":true,\"action\":\"reset\",\"chain\":\"$CHAIN\",\"message\":\"Chain $CHAIN has been removed\",\"save_success\":false,\"save_warning\":\"$SAVE_WARNING\"}"
    fi
    exit 0
fi

# ===============================
# ADD: Thêm rules
# ===============================

# Kiểm tra file tồn tại
if [ ! -f "$BLACKLIST" ]; then
    SUCCESS=false
    ERROR_MESSAGE="Blacklist file not found: $BLACKLIST"
    echo "{\"success\":false,\"error\":\"$ERROR_MESSAGE\",\"blacklist_file\":\"$BLACKLIST\",\"ip_count\":0,\"ip_with_port_count\":0,\"skipped_count\":0,\"rules\":[]}"
    exit 1
fi

# Kiểm tra file có rỗng không
if [ ! -s "$BLACKLIST" ]; then
    SUCCESS=false
    ERROR_MESSAGE="Blacklist file is empty: $BLACKLIST"
    echo "{\"success\":false,\"error\":\"$ERROR_MESSAGE\",\"blacklist_file\":\"$BLACKLIST\",\"ip_count\":0,\"ip_with_port_count\":0,\"skipped_count\":0,\"rules\":[]}"
    exit 1
fi

# Tạo chain nếu chưa tồn tại (redirect output)
if ! iptables -N "$CHAIN" >/dev/null 2>&1; then
    # Chain đã tồn tại, không phải lỗi
    :
fi

# Flush chain (xóa tất cả rules cũ trước khi thêm mới)
iptables -F "$CHAIN" >/dev/null 2>&1 || {
    SUCCESS=false
    ERROR_MESSAGE="Failed to flush chain $CHAIN"
}

# Add rule drop IP
# Sử dụng cách đọc file khác để xử lý dòng cuối không có newline
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && {
        ((SKIPPED_COUNT++))
        continue
    }
    
    # Trim whitespace
    line=$(echo "$line" | xargs)
    
    # Skip nếu sau khi trim vẫn rỗng
    [ -z "$line" ] && {
        ((SKIPPED_COUNT++))
        continue
    }
    
    # Parse format: IP:PORT:DIRECTION hoặc IP:PORT hoặc IP
    # Tách IP và phần còn lại
    if [[ "$line" =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?)(:.*)?$ ]] || \
       [[ "$line" =~ ^([0-9a-fA-F:]+(/[0-9]{1,3})?)(:.*)?$ ]]; then
        IP="${BASH_REMATCH[1]}"
        REST="${BASH_REMATCH[3]}"
        
        # Parse phần còn lại: PORT:DIRECTION hoặc PORT hoặc rỗng
        PORT_INFO=""
        DIRECTION=""
        
        if [ -n "$REST" ]; then
            # Có phần sau IP, bỏ dấu : đầu tiên
            REST="${REST#:}"
            if [ -n "$REST" ]; then
                # Tách bằng dấu :
                IFS=':' read -ra PARTS <<< "$REST"
                if [ ${#PARTS[@]} -ge 1 ] && [ -n "${PARTS[0]}" ]; then
                    PORT_INFO="${PARTS[0]}"
                fi
                if [ ${#PARTS[@]} -ge 2 ] && [ -n "${PARTS[1]}" ]; then
                    DIRECTION="${PARTS[1]}"
                fi
            fi
        fi
        
        # Mặc định direction là inbound nếu không chỉ định
        DIRECTION="${DIRECTION:-inbound}"
        
        # Xác định chain target và match option dựa trên direction
        if [ "$DIRECTION" = "outbound" ]; then
            CHAIN_TARGET="OUTPUT"
            IP_MATCH="-d"  # Outbound: block traffic đi RA đến IP này
        else
            CHAIN_TARGET="INPUT"
            IP_MATCH="-s"  # Inbound: block traffic đi VÀO từ IP này
        fi
        
        RULE_DESC="$line"
        
        if [ -n "$PORT_INFO" ]; then
            # Có port
            if [[ "$PORT_INFO" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                # Port range
                PORT_START="${BASH_REMATCH[1]}"
                PORT_END="${BASH_REMATCH[2]}"
                # Đảm bảo chain được gắn vào INPUT/OUTPUT (redirect output)
                if ! iptables -C "$CHAIN_TARGET" -j "$CHAIN" >/dev/null 2>&1; then
                    iptables -I "$CHAIN_TARGET" 1 -j "$CHAIN" >/dev/null 2>&1
                fi
                # Thêm rules cho TCP và UDP (redirect output)
                # Sử dụng IP_MATCH thay vì -s
                if iptables -A "$CHAIN" $IP_MATCH "$IP" -p tcp --dport "$PORT_START:$PORT_END" -j DROP >/dev/null 2>&1; then
                    iptables -A "$CHAIN" $IP_MATCH "$IP" -p udp --dport "$PORT_START:$PORT_END" -j DROP >/dev/null 2>&1
                    ((IP_WITH_PORT_COUNT++))
                    RULES+=("$RULE_DESC")
                else
                    SUCCESS=false
                    ERROR_MESSAGE="Failed to add rule for: $RULE_DESC"
                fi
            else
                # Single port - kiểm tra xem có phải là số không
                if [[ "$PORT_INFO" =~ ^[0-9]+$ ]]; then
                    PORT="$PORT_INFO"
                    # Đảm bảo chain được gắn vào INPUT/OUTPUT (redirect output)
                    if ! iptables -C "$CHAIN_TARGET" -j "$CHAIN" >/dev/null 2>&1; then
                        iptables -I "$CHAIN_TARGET" 1 -j "$CHAIN" >/dev/null 2>&1
                    fi
                    # Thêm rules cho TCP và UDP (redirect output)
                    # Sử dụng IP_MATCH thay vì -s
                    if iptables -A "$CHAIN" $IP_MATCH "$IP" -p tcp --dport "$PORT" -j DROP >/dev/null 2>&1; then
                        iptables -A "$CHAIN" $IP_MATCH "$IP" -p udp --dport "$PORT" -j DROP >/dev/null 2>&1
                        ((IP_WITH_PORT_COUNT++))
                        RULES+=("$RULE_DESC")
                    else
                        SUCCESS=false
                        ERROR_MESSAGE="Failed to add rule for: $RULE_DESC"
                    fi
                else
                    # Port không hợp lệ
                    ((SKIPPED_COUNT++))
                fi
            fi
        else
            # Chỉ IP, không có port - block toàn bộ traffic
            # Đảm bảo chain được gắn vào INPUT/OUTPUT (redirect output)
            if ! iptables -C "$CHAIN_TARGET" -j "$CHAIN" >/dev/null 2>&1; then
                iptables -I "$CHAIN_TARGET" 1 -j "$CHAIN" >/dev/null 2>&1
            fi
            # Sử dụng IP_MATCH thay vì -s
            if iptables -A "$CHAIN" $IP_MATCH "$IP" -j DROP >/dev/null 2>&1; then
                ((IP_COUNT++))
                RULES+=("$RULE_DESC")
            else
                SUCCESS=false
                ERROR_MESSAGE="Failed to add rule for IP: $IP"
            fi
        fi
    else
        ((SKIPPED_COUNT++))
    fi
done < "$BLACKLIST"

# Save rules
SAVE_SUCCESS=true
SAVE_METHOD=""
SAVE_WARNING=""

if command -v netfilter-persistent >/dev/null 2>&1; then
    if netfilter-persistent save >/dev/null 2>&1; then
        SAVE_METHOD="netfilter-persistent"
    else
        SAVE_SUCCESS=false
        SAVE_WARNING="Failed to save with netfilter-persistent"
    fi
elif command -v iptables-save >/dev/null 2>&1; then
    # Tạo thư mục nếu chưa tồn tại
    if [ ! -d "/etc/iptables" ]; then
        mkdir -p /etc/iptables >/dev/null 2>&1 || {
            SAVE_WARNING="Cannot create /etc/iptables directory, rules not persisted"
            SAVE_SUCCESS=false
        }
    fi
    
    if [ -d "/etc/iptables" ]; then
        if iptables-save > /etc/iptables/rules.v4 2>/dev/null; then
            SAVE_METHOD="iptables-save"
        else
            SAVE_SUCCESS=false
            SAVE_WARNING="Failed to save iptables rules"
        fi
    fi
fi

# Convert rules array to JSON array
RULES_JSON="["
for i in "${!RULES[@]}"; do
    if [ $i -gt 0 ]; then
        RULES_JSON+=","
    fi
    RULES_JSON+="\"${RULES[$i]}\""
done
RULES_JSON+="]"

# Output JSON - Không fail nếu chỉ lỗi save (rules đã được apply)
if [ "$SUCCESS" = true ]; then
    if [ "$SAVE_SUCCESS" = true ]; then
        echo "{\"success\":true,\"action\":\"add\",\"blacklist_file\":\"$BLACKLIST\",\"chain\":\"$CHAIN\",\"ip_count\":$IP_COUNT,\"ip_with_port_count\":$IP_WITH_PORT_COUNT,\"skipped_count\":$SKIPPED_COUNT,\"save_method\":\"$SAVE_METHOD\",\"rules\":$RULES_JSON,\"message\":\"Applied blacklist from $BLACKLIST\"}"
    else
        # Rules đã được apply nhưng không save được
        echo "{\"success\":true,\"action\":\"add\",\"blacklist_file\":\"$BLACKLIST\",\"chain\":\"$CHAIN\",\"ip_count\":$IP_COUNT,\"ip_with_port_count\":$IP_WITH_PORT_COUNT,\"skipped_count\":$SKIPPED_COUNT,\"save_success\":false,\"save_warning\":\"$SAVE_WARNING\",\"rules\":$RULES_JSON,\"message\":\"Applied blacklist from $BLACKLIST (rules not persisted)\"}"
    fi
else
    ERROR_MSG="${ERROR_MESSAGE:-Unknown error}"
    echo "{\"success\":false,\"action\":\"add\",\"error\":\"$ERROR_MSG\",\"blacklist_file\":\"$BLACKLIST\",\"chain\":\"$CHAIN\",\"ip_count\":$IP_COUNT,\"ip_with_port_count\":$IP_WITH_PORT_COUNT,\"skipped_count\":$SKIPPED_COUNT,\"save_success\":$SAVE_SUCCESS,\"rules\":$RULES_JSON}"
    exit 1
fi