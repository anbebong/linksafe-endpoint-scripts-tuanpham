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

# Lấy thông tin VGA devices từ lspci
vga_output=$(lspci | grep VGA 2>/dev/null || echo "")

# Lấy thông tin display từ xrandr (nếu có X server)
xrandr_output=$(xrandr 2>/dev/null | grep -E " connected|*" | head -10 || echo "")

# Lấy thông tin OpenGL từ glxinfo (nếu có)
glxinfo_output=$(glxinfo 2>/dev/null | grep -E "OpenGL|GLX" | head -10 || echo "")

# Parse video controllers
video_controllers="[]"
if [ -n "$vga_output" ]; then
    video_controllers="["
    first=true

    echo "$vga_output" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            # Parse lspci VGA line: "00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 620 (rev 07)"
            bus_id=$(echo "$line" | cut -d' ' -f1)
            device_info=$(echo "$line" | cut -d':' -f3- | sed 's/^ *//')

            if [ "$first" = true ]; then
                first=false
            else
                video_controllers="${video_controllers},"
            fi

            video_controllers="${video_controllers}{\"bus_id\":\"${bus_id}\",\"device_info\":\"${device_info}\",\"type\":\"VGA\"}"
        fi
    done

    video_controllers="${video_controllers}]"
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