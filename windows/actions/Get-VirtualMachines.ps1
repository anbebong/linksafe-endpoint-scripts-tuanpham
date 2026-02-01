#Requires -Version 5.1
<#
.SYNOPSIS
    Thu thập thông tin Virtual Machines trên Windows

.DESCRIPTION
    Thu thập thông tin về các máy ảo đang chạy trên hệ thống Windows
#>

# Nhập các module cần thiết
$LibPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib"
$WUModulePath = Join-Path $LibPath "WindowsUpdate.psm1"

Import-Module $WUModulePath -Force -ErrorAction SilentlyContinue

# Thiết lập alias cho logging
if (Get-Command Write-PatchLog -ErrorAction SilentlyContinue) {
    # Sử dụng function từ module
} else {
    # Sử dụng fallback local
    function Write-PatchLog {
        param([string]$Message, [string]$Level = 'INFO')
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        Write-Output "LOG:${timestamp}:${Level}:${Message}"
    }
}

if (Get-Command Write-PatchData -ErrorAction SilentlyContinue) {
    # Sử dụng function từ module
} else {
    # Sử dụng fallback local
    function Write-PatchData {
        param([string]$JsonData)
        Write-Output "DATA:$JsonData"
    }
}

# Thu thập thông tin Virtual Machines
$virtualMachines = @()

# Kiểm tra Hyper-V VMs
try {
    $hypervVMs = Get-VM -ErrorAction SilentlyContinue
    foreach ($vm in $hypervVMs) {
        $vmNetworkAdapters = Get-VMNetworkAdapter -VM $vm -ErrorAction SilentlyContinue
        $networkInfo = @()
        foreach ($adapter in $vmNetworkAdapters) {
            $networkInfo += @{
                name = $adapter.Name
                mac_address = $adapter.MacAddress
                switch_name = $adapter.SwitchName
                ip_addresses = $adapter.IPAddresses
            }
        }

        $virtualMachines += [ordered]@{
            name = $vm.Name
            id = $vm.Id
            state = $vm.State.ToString()
            platform = "Hyper-V"
            cpu_count = $vm.ProcessorCount
            memory_mb = $vm.MemoryStartup / 1MB
            memory_max_mb = $vm.MemoryMaximum / 1MB
            generation = $vm.Generation
            network_adapters = $networkInfo
            notes = $vm.Notes
        }
    }
} catch {
    # Im lặng khi Hyper-V không khả dụng
}

# Kiểm tra VMware VMs (nếu có VMware Workstation/Player)
try {
    $vmwarePath = "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe"
    if (Test-Path $vmwarePath) {
        $vmrunOutput = & $vmwarePath list 2>$null
        if ($LASTEXITCODE -eq 0) {
            $vmPaths = $vmrunOutput | Where-Object { $_ -match '\.vmx$' }
            foreach ($vmPath in $vmPaths) {
                $vmName = [System.IO.Path]::GetFileNameWithoutExtension($vmPath)
                $virtualMachines += [ordered]@{
                    name = $vmName
                    id = $vmPath
                    state = "Unknown"
                    platform = "VMware"
                    cpu_count = "Unknown"
                    memory_mb = "Unknown"
                    memory_max_mb = "Unknown"
                    generation = "Unknown"
                    network_adapters = @()
                    notes = "VMware VM detected via vmrun"
                }
            }
        }
    }
} catch {
    # Im lặng khi VMware không khả dụng
}

# Kiểm tra VirtualBox VMs (nếu có VirtualBox)
try {
    $vboxPath = "${env:ProgramFiles}\Oracle\VirtualBox\VBoxManage.exe"
    if (Test-Path $vboxPath) {
        $vboxOutput = & $vboxPath list vms 2>$null
        if ($LASTEXITCODE -eq 0) {
            $vboxVMs = $vboxOutput | Where-Object { $_ -match '"(.+)" \{(.*)\}' } | ForEach-Object {
                if ($_ -match '"(.+)" \{(.*)\}') {
                    $vmName = $matches[1]
                    $vmId = $matches[2]
                    @{
                        name = $vmName
                        id = $vmId
                    }
                }
            }

            foreach ($vm in $vboxVMs) {
                $virtualMachines += [ordered]@{
                    name = $vm.name
                    id = $vm.id
                    state = "Unknown"
                    platform = "VirtualBox"
                    cpu_count = "Unknown"
                    memory_mb = "Unknown"
                    memory_max_mb = "Unknown"
                    generation = "Unknown"
                    network_adapters = @()
                    notes = "VirtualBox VM detected"
                }
            }
        }
    }
} catch {
    # Im lặng khi VirtualBox không khả dụng
}

# Tạo kết quả JSON
$result = @{
    status = "success"
    data = @{
        hostname = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        virtual_machines = $virtualMachines
    }
}

$jsonResult = $result | ConvertTo-Json -Depth 10 -Compress
Write-Output $jsonResult