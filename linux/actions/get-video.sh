#!/bin/bash
# Script thu thập thông tin Video/Graphics trên Linux

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Lấy thông tin VGA devices từ lshw
lshw_output=$(lshw -class display 2>/dev/null || echo "")

# Lấy thông tin display từ xrandr (nếu có X server)
if [ -n "${DISPLAY:-}" ]; then
    xrandr_output=$(xrandr 2>/dev/null | grep -E " connected|*" | head -10 || echo "")
else
    xrandr_output=""
fi

# Lấy thông tin OpenGL từ glxinfo (nếu có)
if [ -n "${DISPLAY:-}" ]; then
    glxinfo_output=$(glxinfo 2>/dev/null | grep -E "OpenGL|GLX" | head -10 || echo "")
else
    glxinfo_output=""
fi

# Parse video controllers
video_controllers="[]"
if [ -n "$lshw_output" ]; then
    video_controllers="["$(
        echo "$lshw_output" | grep -E "product:|vendor:|description:" | paste - - - | awk -F'\t' '
        {
            desc_line = $1
            prod_line = $2
            vend_line = $3
            sub(/.*description: /, "", desc_line)
            sub(/.*product: /, "", prod_line)
            sub(/.*vendor: /, "", vend_line)
            printf "{\"product\":\"%s\",\"vendor\":\"%s\",\"description\":\"%s\"},", prod_line, vend_line, desc_line
        }
        ' | sed 's/,$//'
    )"]"
fi

# Parse display information
display_info="{}"
if [ -n "$xrandr_output" ]; then
    # Extract connected displays and resolutions
    connected_displays=$(echo "$xrandr_output" | grep " connected" | wc -l)
    primary_resolution=$(echo "$xrandr_output" | grep -A1 " connected" | grep -E "[0-9]+x[0-9]+" | head -1 | awk '{print $1}' || echo "")

    display_info="{\"connected_displays\":${connected_displays},\"primary_resolution\":\"${primary_resolution}\"}"
fi

# Parse OpenGL information
opengl_info="{}"
if [ -n "$glxinfo_output" ]; then
    opengl_vendor=$(echo "$glxinfo_output" | grep "OpenGL vendor string:" | sed 's/.*: //' | sed 's/"/\\"/g' || echo "")
    opengl_renderer=$(echo "$glxinfo_output" | grep "OpenGL renderer string:" | sed 's/.*: //' | sed 's/"/\\"/g' || echo "")
    opengl_version=$(echo "$glxinfo_output" | grep "OpenGL version string:" | sed 's/.*: //' | sed 's/"/\\"/g' || echo "")

    opengl_info="{\"vendor\":\"${opengl_vendor}\",\"renderer\":\"${opengl_renderer}\",\"version\":\"${opengl_version}\"}"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"video_graphics\":{\"controllers\":${video_controllers},\"display\":${display_info},\"opengl\":${opengl_info}}}}"

# Xuất JSON kết quả
echo "$result"