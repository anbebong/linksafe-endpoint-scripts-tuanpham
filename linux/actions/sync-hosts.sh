#!/bin/bash

## Run Script: 
## sync-hosts.sh EditHosts.txt
## Default: EditHosts.txt

HOST_FILE="/etc/hosts"

# Tham số đầu vào: file danh sách hosts
INPUT_FILE="${1:-/tmp/EditHosts.txt}"

# Nếu là path tương đối → đặt trong /tmp
if [[ "$INPUT_FILE" != /* ]]; then
    INPUT_FILE="/tmp/$INPUT_FILE"
fi

START_MARKER="// start list sync host"
END_MARKER="// end list sync host"

# Check root
if [ "$(id -u)" -ne 0 ]; then
  echo "{\"status\":\"failed\",\"message\":\"Please run as root\"}"
  exit 1
fi

# Backup
BACKUP_FILE="${HOST_FILE}.bak.$(date +%F_%H%M%S)"
cp "$HOST_FILE" "$BACKUP_FILE"

# Build new block content
NEW_BLOCK=""

while IFS= read -r line || [ -n "$line" ]; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  ip=$(echo "$line" | awk '{print $1}')
  host=$(echo "$line" | awk '{print $2}')

  hostname=$(echo "$host" \
    | sed -E 's~^https?://~~' \
    | sed 's~/.*~~')

  NEW_BLOCK="${NEW_BLOCK}${ip}\t${hostname}
"
done < "$INPUT_FILE"

# Check markers exist
HAS_START=$(grep -Fx "$START_MARKER" "$HOST_FILE")
HAS_END=$(grep -Fx "$END_MARKER" "$HOST_FILE")

if [[ -z "$HAS_START" || -z "$HAS_END" ]]; then
  {
    cat "$HOST_FILE"
    echo
    echo "$START_MARKER"
    printf "%s" "$NEW_BLOCK"
    echo "$END_MARKER"
  } > /tmp/hosts.new

else
  # Giữ nguyên logic AWK của bạn, chỉ sửa printf thành print để hết lỗi runtime
  awk -v start="$START_MARKER" \
    -v end="$END_MARKER" \
    -v block="$NEW_BLOCK" '
$0 == start {
  print start
  # Dùng print để đẩy cả khối NEW_BLOCK của bạn ra mà không bị lỗi format
  print block
  inblock = 1
  next
}
$0 == end {
  print end
  inblock = 0
  next
}
!inblock {
  print
}
' "$HOST_FILE" > /tmp/hosts.new
fi

if mv /tmp/hosts.new "$HOST_FILE"; then
  echo "{\"status\":\"success\",\"data\":{\"host_file\":\"$HOST_FILE\",\"backup\":\"$BACKUP_FILE\"}}"
else
  echo "{\"status\":\"failed\",\"message\":\"mv failed\"}"
  exit 1
fi
