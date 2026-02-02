#!/bin/bash
# Script thu thập thông tin Virtual Machines trên Linux

# Lấy đường dẫn script và thư mục gốc
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Nạp các thư viện chung
source "${BASE_DIR}/lib/common.sh"

# Thu thập dữ liệu
hostname=$(get_hostname)
timestamp=$(get_timestamp)

# Collect virtual machines
vm_list=""

# Kiểm tra KVM/libvirt VMs
if command -v virsh >/dev/null 2>&1; then
    virsh_output=$(virsh list --all 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$virsh_output" ]; then
        vm_list+=$(
            echo "$virsh_output" | awk '
            NR > 2 && $1 !~ /^-/ && NF >= 3 {
                id = $1
                name = $2
                state = $3
                # Escape quotes
                gsub(/"/, "\\\"", name)
                printf "{\"name\":\"%s\",\"id\":\"%s\",\"state\":\"%s\",\"platform\":\"KVM\",\"cpu_count\":\"Unknown\",\"memory_mb\":\"Unknown\",\"memory_max_mb\":\"Unknown\",\"generation\":\"Unknown\",\"network_adapters\":[],\"notes\":\"KVM/libvirt VM\"},", name, id, state
            }
            '
        )
    fi
fi

# Kiểm tra VirtualBox VMs
if command -v VBoxManage >/dev/null 2>&1; then
    vbox_output=$(VBoxManage list vms 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$vbox_output" ]; then
        vm_list+=$(
            echo "$vbox_output" | awk '
            /"[^"]*" \{[^}]*\}/ {
                match($0, /"([^"]*)"/, name_arr)
                match($0, /\{([^}]*)\}/, id_arr)
                name = name_arr[1]
                id = id_arr[1]
                # Escape quotes
                gsub(/"/, "\\\"", name)
                printf "{\"name\":\"%s\",\"id\":\"%s\",\"state\":\"Unknown\",\"platform\":\"VirtualBox\",\"cpu_count\":\"Unknown\",\"memory_mb\":\"Unknown\",\"memory_max_mb\":\"Unknown\",\"generation\":\"Unknown\",\"network_adapters\":[],\"notes\":\"VirtualBox VM\"},", name, id
            }
            '
        )
    fi
fi

# Kiểm tra VMware VMs
if command -v vmrun >/dev/null 2>&1; then
    vmrun_output=$(vmrun list 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$vmrun_output" ]; then
        vm_list+=$(
            echo "$vmrun_output" | awk '
            /\.vmx$/ {
                path = $0
                # Extract name from path
                n = split(path, arr, "/")
                name = arr[n]
                sub(/\.vmx$/, "", name)
                # Escape quotes
                gsub(/"/, "\\\"", name)
                printf "{\"name\":\"%s\",\"id\":\"%s\",\"state\":\"Unknown\",\"platform\":\"VMware\",\"cpu_count\":\"Unknown\",\"memory_mb\":\"Unknown\",\"memory_max_mb\":\"Unknown\",\"generation\":\"Unknown\",\"network_adapters\":[],\"notes\":\"VMware VM\"},", name, path
            }
            '
        )
    fi
fi

# Kiểm tra Docker containers đang chạy
if command -v docker >/dev/null 2>&1; then
    docker_output=$(docker ps --format "{{.Names}}\t{{.ID}}\t{{.Status}}\t{{.Image}}" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$docker_output" ]; then
        vm_list+=$(
            echo "$docker_output" | awk -F'\t' '
            NF == 4 {
                name = $1
                id = $2
                status = $3
                image = $4
                # Escape quotes
                gsub(/"/, "\\\"", name)
                gsub(/"/, "\\\"", status)
                printf "{\"name\":\"%s\",\"id\":\"%s\",\"state\":\"%s\",\"platform\":\"Docker\",\"cpu_count\":\"Unknown\",\"memory_mb\":\"Unknown\",\"memory_max_mb\":\"Unknown\",\"generation\":\"Unknown\",\"network_adapters\":[],\"notes\":\"Docker container - %s\"},", name, id, status, image
            }
            '
        )
    fi
fi

# Kiểm tra Kubernetes pods
if command -v kubectl >/dev/null 2>&1; then
    k8s_output=$(kubectl get pods --all-namespaces -o json 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$k8s_output" ]; then
        vm_list+=$(
            echo "$k8s_output" | jq -r '.items[] | select(.status.phase == "Running") | "\(.metadata.name)\t\(.metadata.namespace)\t\(.status.phase)\t\(.spec.containers[0].image)"' 2>/dev/null | awk -F'\t' '
            NF == 4 {
                name = $1
                namespace = $2
                phase = $3
                image = $4
                # Escape quotes
                gsub(/"/, "\\\"", name)
                printf "{\"name\":\"%s\",\"id\":\"%s/%s\",\"state\":\"%s\",\"platform\":\"Kubernetes\",\"cpu_count\":\"Unknown\",\"memory_mb\":\"Unknown\",\"memory_max_mb\":\"Unknown\",\"generation\":\"Unknown\",\"network_adapters\":[],\"notes\":\"K8s pod - %s\"},", name, namespace, name, phase, image
            }
            '
        )
    fi
fi

# Build JSON array
if [ -n "$vm_list" ]; then
    vm_list=${vm_list%,}  # Remove trailing comma
    virtual_machines="[$vm_list]"
else
    virtual_machines="[]"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"virtual_machines\":${virtual_machines}}}"

# Xuất JSON kết quả
echo "$result"