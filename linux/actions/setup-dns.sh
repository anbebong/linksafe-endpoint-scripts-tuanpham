#!/bin/bash

# Nhận tham số hoặc dùng mặc định
DNS1=${1:-"8.8.8.8"}
DNS2=${2:-"8.8.4.4"}
RESOLV_CONF="/etc/resolv.conf"
echo "start setup-dns"
# Kiểm tra quyền sudo để ghi file
if [ "$EUID" -ne 0 ]; then 
  echo "{\"status\": \"error\", \"data\": \"Requires root privileges\"}"
  exit 1
fi

# Thực hiện ghi cấu hình
echo "nameserver $DNS1" > $RESOLV_CONF
echo "nameserver $DNS2" >> $RESOLV_CONF

# Kiểm tra nhanh server đang hoạt động
ACTIVE_DNS=$(nslookup google.com 2>/dev/null | grep "Server" | awk '{print $2}' | head -n 1)

# Trả về kết quả JSON rút gọn
cat <<EOF
{
  "status": "success",
  "data": {
    "primary_dns": "$DNS1",
    "secondary_dns": "$DNS2",
    "applied_at": "$(date '+%Y-%m-%d %H:%M:%S')"
  }
}
EOF
