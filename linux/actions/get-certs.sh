#!/bin/bash

# Các thư mục chứa Cert phổ biến trên Linux
CERT_PATHS=("/etc/ssl/certs" "/usr/local/share/ca-certificates" "/etc/pki/tls/certs")

echo "--- DANH SÁCH CHỨNG CHỈ HỆ THỐNG ---"
echo "--------------------------------------------------------------------------------"

for path in "${CERT_PATHS[@]}"; do
    if [ -d "$path" ]; then
        # Tìm các file có đuôi .crt, .pem hoặc .cer
        find "$path" -name "*.pem" -o -name "*.crt" | while read -r cert_file; do
            # Trích xuất thông tin bằng openssl
            # subject: Tên chủ thể, enddate: Ngày hết hạn, issuer: Nhà phát hành
            data=$(openssl x509 -in "$cert_file" -noout -subject -enddate -issuer 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                subject=$(echo "$data" | grep "subject" | sed 's/subject=//g')
                expiry=$(echo "$data" | grep "notAfter" | sed 's/notAfter=//g')
                issuer=$(echo "$data" | grep "issuer" | sed 's/issuer=//g')
                
                # In ra định dạng gọn gàng
                echo "File: $(basename "$cert_file")"
                echo "  - Chủ thể  : $subject"
                echo "  - Hết hạn  : $expiry"
                echo "--------------------------------------------------------------------------------"
            fi
        done
    fi
done
