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

# Parse virtual machines
virtual_machines="[]"

# Kiểm tra KVM/libvirt VMs
if command -v virsh >/dev/null 2>&1; then
    virsh_output=$(virsh list --all 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$virsh_output" ]; then
        # Parse virsh output (skip header lines)
        echo "$virsh_output" | tail -n +3 | while IFS= read -r line; do
            if [ -n "$line" ] && [[ ! $line =~ ^- ]]; then
                vm_id=$(echo "$line" | awk '{print $1}')
                vm_name=$(echo "$line" | awk '{print $2}')
                vm_state=$(echo "$line" | awk '{print $3}')

                # Lấy thêm thông tin chi tiết
                vm_info=$(virsh dominfo "$vm_name" 2>/dev/null)
                cpu_count="Unknown"
                memory_mb="Unknown"
                max_memory_mb="Unknown"

                if [ -n "$vm_info" ]; then
                    cpu_count=$(echo "$vm_info" | grep "CPU(s):" | awk '{print $2}')
                    memory_mb=$(echo "$vm_info" | grep "Used memory:" | awk '{print $3}' | sed 's/ KiB//')
                    max_memory_mb=$(echo "$vm_info" | grep "Max memory:" | awk '{print $3}' | sed 's/ KiB//')

                    # Convert KiB to MB
                    if [ "$memory_mb" != "Unknown" ]; then
                        memory_mb=$((memory_mb / 1024))
                    fi
                    if [ "$max_memory_mb" != "Unknown" ]; then
                        max_memory_mb=$((max_memory_mb / 1024))
                    fi
                fi

                # Lấy thông tin network
                network_adapters="[]"
                net_info=$(virsh domiflist "$vm_name" 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$net_info" ]; then
                    network_adapters="["
                    first_net=true
                    echo "$net_info" | tail -n +3 | while IFS= read -r net_line; do
                        if [ -n "$net_line" ]; then
                            net_type=$(echo "$net_line" | awk '{print $1}')
                            net_model=$(echo "$net_line" | awk '{print $2}')
                            net_mac=$(echo "$net_line" | awk '{print $3}')
                            net_source=$(echo "$net_line" | awk '{print $4}')

                            if [ "$first_net" = true ]; then
                                first_net=false
                            else
                                network_adapters="${network_adapters},"
                            fi
                            network_adapters="${network_adapters}{\"name\":\"${net_model}\",\"mac_address\":\"${net_mac}\",\"switch_name\":\"${net_source}\",\"ip_addresses\":[]}"
                        fi
                    done
                    network_adapters="${network_adapters}]"
                fi

                if [ -n "$virtual_machines" ] && [ "$virtual_machines" != "[" ]; then
                    virtual_machines="${virtual_machines},"
                fi
                virtual_machines="${virtual_machines}{\"name\":\"${vm_name}\",\"id\":\"${vm_id}\",\"state\":\"${vm_state}\",\"platform\":\"KVM\",\"cpu_count\":\"${cpu_count}\",\"memory_mb\":\"${memory_mb}\",\"memory_max_mb\":\"${max_memory_mb}\",\"generation\":\"Unknown\",\"network_adapters\":${network_adapters},\"notes\":\"KVM/libvirt VM\"}"
            fi
        done
    fi
fi

# Kiểm tra VirtualBox VMs
if command -v VBoxManage >/dev/null 2>&1; then
    vbox_output=$(VBoxManage list vms 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$vbox_output" ]; then
        echo "$vbox_output" | while IFS= read -r line; do
            if [[ $line =~ \"(.+)\" \{(.+)\} ]]; then
                vm_name="${BASH_REMATCH[1]}"
                vm_id="${BASH_REMATCH[2]}"

                # Lấy trạng thái VM
                vm_state="Unknown"
                state_output=$(VBoxManage showvminfo "$vm_name" --machinereadable 2>/dev/null | grep "^VMState=")
                if [ -n "$state_output" ]; then
                    vm_state=$(echo "$state_output" | sed 's/VMState="//;s/"//')
                fi

                if [ -n "$virtual_machines" ] && [ "$virtual_machines" != "[" ]; then
                    virtual_machines="${virtual_machines},"
                fi
                virtual_machines="${virtual_machines}{\"name\":\"${vm_name}\",\"id\":\"${vm_id}\",\"state\":\"${vm_state}\",\"platform\":\"VirtualBox\",\"cpu_count\":\"Unknown\",\"memory_mb\":\"Unknown\",\"memory_max_mb\":\"Unknown\",\"generation\":\"Unknown\",\"network_adapters\":[],\"notes\":\"VirtualBox VM\"}"
            fi
        done
    fi
fi

# Kiểm tra VMware VMs
if command -v vmrun >/dev/null 2>&1; then
    vmrun_output=$(vmrun list 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$vmrun_output" ]; then
        echo "$vmrun_output" | while IFS= read -r line; do
            if [[ $line =~ \.vmx$ ]]; then
                vm_path="$line"
                vm_name=$(basename "$vm_path" .vmx)

                if [ -n "$virtual_machines" ] && [ "$virtual_machines" != "[" ]; then
                    virtual_machines="${virtual_machines},"
                fi
                virtual_machines="${virtual_machines}{\"name\":\"${vm_name}\",\"id\":\"${vm_path}\",\"state\":\"Unknown\",\"platform\":\"VMware\",\"cpu_count\":\"Unknown\",\"memory_mb\":\"Unknown\",\"memory_max_mb\":\"Unknown\",\"generation\":\"Unknown\",\"network_adapters\":[],\"notes\":\"VMware VM\"}"
            fi
        done
    fi
fi

# Kiểm tra Docker containers (có thể coi như lightweight VMs)
if command -v docker >/dev/null 2>&1; then
    docker_output=$(docker ps -a --format "table {{.Names}}\t{{.ID}}\t{{.Status}}\t{{.Image}}" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$docker_output" ]; then
        echo "$docker_output" | tail -n +2 | while IFS= read -r line; do
            if [ -n "$line" ]; then
                container_name=$(echo "$line" | awk '{print $1}')
                container_id=$(echo "$line" | awk '{print $2}')
                container_status=$(echo "$line" | awk '{print $3}')
                container_image=$(echo "$line" | awk '{print $4}')

                if [ -n "$virtual_machines" ] && [ "$virtual_machines" != "[" ]; then
                    virtual_machines="${virtual_machines},"
                fi
                virtual_machines="${virtual_machines}{\"name\":\"${container_name}\",\"id\":\"${container_id}\",\"state\":\"${container_status}\",\"platform\":\"Docker\",\"cpu_count\":\"Unknown\",\"memory_mb\":\"Unknown\",\"memory_max_mb\":\"Unknown\",\"generation\":\"Unknown\",\"network_adapters\":[],\"notes\":\"Docker container - ${container_image}\"}"
            fi
        done
    fi
fi

if [ "$virtual_machines" = "[" ]; then
    virtual_machines="[]"
else
    virtual_machines="${virtual_machines}]"
fi

# Tạo JSON kết quả minified
result="{\"status\":\"success\",\"data\":{\"hostname\":\"${hostname}\",\"timestamp\":\"${timestamp}\",\"virtual_machines\":${virtual_machines}}}"

# Xuất JSON kết quả
echo "$result"