#!/bin/bash

## Run Script:
## set-proxy.sh 192.168.100.244 8888 "localhost,127.0.0.1,.svc,.cluster.local"
## set-proxy.sh --reset
## Default: 192.168.100.244 8888 "localhost,127.0.0.1,.svc,.cluster.local"

# Check root
if [ "$(id -u)" -ne 0 ]; then
  echo "{\"status\":\"failed\",\"message\":\"Root privileges required\"}"
  exit 1
fi

# Chế độ RESET
if [[ "$1" == "reset" || "$1" == "--reset" ]]; then
  sed -i '/_proxy=/I d' /etc/environment
  sed -i '/_PROXY=/I d' /etc/environment
  rm -f /etc/apt/apt.conf.d/99proxy /etc/profile.d/proxy.sh
  if command -v gsettings >/dev/null; then
    gsettings set org.gnome.system.proxy mode 'none'
  fi
  echo "{\"status\":\"reset_success\"}"
  exit 0
fi

# Thông số đầu vào
PROXY_IP="${1:-192.168.100.244}"
PROXY_PORT="${2:-8888}"
# Chuỗi NO_PROXY cần được giữ nguyên giá trị truyền vào
NO_PROXY="${3:-localhost,127.0.0.1,::1,.local,.svc,.cluster.local}"
PROXY_URL="http://${PROXY_IP}:${PROXY_PORT}"

# --- CẤU HÌNH ---

# 1. Xử lý /etc/environment (Xóa sạch các dòng cũ liên quan đến proxy bất kể hoa thường)
# Dùng grep -v để tạo file tạm rồi ghi đè là cách an toàn nhất thay vì sed -i phức tạp
grep -vi "_proxy=" /etc/environment > /etc/environment.tmp
mv /etc/environment.tmp /etc/environment

# Ghi giá trị mới vào /etc/environment
# Quan trọng: NO_PROXY phải nằm trong nháy kép
cat >> /etc/environment <<EOF
http_proxy="${PROXY_URL}"
https_proxy="${PROXY_URL}"
no_proxy="${NO_PROXY}"
HTTP_PROXY="${PROXY_URL}"
HTTPS_PROXY="${PROXY_URL}"
NO_PROXY="${NO_PROXY}"
EOF

# 2. Cấu hình APT
cat > /etc/apt/apt.conf.d/99proxy <<EOF
Acquire::http::Proxy "${PROXY_URL}";
Acquire::https::Proxy "${PROXY_URL}";
EOF

# 3. Cấu hình profile.d (Dành cho shell)
cat > /etc/profile.d/proxy.sh <<EOF
export http_proxy="${PROXY_URL}"
export https_proxy="${PROXY_URL}"
export no_proxy="${NO_PROXY}"
export HTTP_PROXY="${PROXY_URL}"
export HTTPS_PROXY="${PROXY_URL}"
export NO_PROXY="${NO_PROXY}"
EOF
chmod +x /etc/profile.d/proxy.sh

# 4. GNOME Desktop Settings (Nếu có giao diện)
CURRENT_USER=$(logname 2>/dev/null || echo $SUDO_USER)
if [ -n "$CURRENT_USER" ] && command -v gsettings >/dev/null; then
    # Chuyển NO_PROXY sang định dạng mảng cho gsettings (ví dụ: ['localhost', '127.0.0.1'])
    GNOME_NO_PROXY=$(echo "'$NO_PROXY'" | sed "s/,/', '/g")
    
    sudo -u "$CURRENT_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $CURRENT_USER)/bus" \
      bash -c "gsettings set org.gnome.system.proxy mode 'manual' && \
               gsettings set org.gnome.system.proxy.http host '$PROXY_IP' && \
               gsettings set org.gnome.system.proxy.http port $PROXY_PORT && \
               gsettings set org.gnome.system.proxy.https host '$PROXY_IP' && \
               gsettings set org.gnome.system.proxy.https port $PROXY_PORT && \
               gsettings set org.gnome.system.proxy ignore-hosts \"[$GNOME_NO_PROXY]\""
fi

# --- PHẢN HỒI JSON ---
# Kiểm tra lại xem file đã lưu đúng chưa
FINAL_NO_PROXY=$(grep -i "no_proxy=" /etc/environment | head -n 1 | cut -d'"' -f2)

echo "{\"status\":\"success\",\"data\":{\"proxy\":\"${PROXY_URL}\",\"no_proxy\":\"${FINAL_NO_PROXY}\",\"scope\":\"system-wide\"}}"
