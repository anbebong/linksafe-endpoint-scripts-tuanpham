#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - DNF/YUM Package Manager Library
# =============================================================================
# DNF/YUM implementation for RHEL/CentOS/Fedora/Rocky/AlmaLinux
# Reference: Rudder yum.rs implementation
# =============================================================================

# Source common library if not already sourced
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/../lib"
if [[ -z "${LINKSAFE_PATCH_VERSION:-}" ]]; then
    source "${LIB_DIR}/common.sh"
fi

# =============================================================================
# DNF/YUM DETECTION
# =============================================================================

# Detect which package manager to use
if command_exists dnf; then
    readonly PKG_MGR="dnf"
    readonly PKG_MGR_CMD="dnf"
else
    readonly PKG_MGR="yum"
    readonly PKG_MGR_CMD="yum"
fi

readonly RPM="rpm"

log_debug "Using package manager: ${PKG_MGR}"

# =============================================================================
# CACHE MANAGEMENT
# =============================================================================

# Update package cache
dnf_update_cache() {
    log_info "Updating ${PKG_MGR} package cache..."

    local output
    if output=$($PKG_MGR_CMD makecache -q 2>&1); then
        log_info "${PKG_MGR} cache updated successfully"
        return 0
    else
        log_error "Failed to update ${PKG_MGR} cache: ${output}"
        return 1
    fi
}

# =============================================================================
# PACKAGE LISTING
# =============================================================================

# List all available updates
dnf_list_updates() {
    log_debug "Listing available ${PKG_MGR} updates..."

    local updates=()
    local total=0
    local security_count=0

    # Get check-update output (returns exit code 100 if updates available)
    local check_output
    check_output=$($PKG_MGR_CMD check-update -q 2>/dev/null) || true

    while IFS= read -r line; do
        # Skip empty lines and headers
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^Last\ metadata ]] && continue
        [[ "$line" =~ ^Obsoleting ]] && continue

        # Parse line: package-name.arch  version  repository
        local parts
        read -ra parts <<< "$line"

        [[ ${#parts[@]} -lt 3 ]] && continue

        local full_name="${parts[0]}"
        local new_version="${parts[1]}"
        local repository="${parts[2]}"

        # Split package name and architecture
        local package_name arch
        if [[ "$full_name" =~ ^(.+)\.([^.]+)$ ]]; then
            package_name="${BASH_REMATCH[1]}"
            arch="${BASH_REMATCH[2]}"
        else
            package_name="$full_name"
            arch="unknown"
        fi

        # Get current installed version
        local current_version
        current_version=$($RPM -q --qf '%{VERSION}-%{RELEASE}' "$package_name" 2>/dev/null || echo "unknown")

        # Check if security update
        local is_security="false"
        # Check using updateinfo if available
        if $PKG_MGR_CMD updateinfo list --security 2>/dev/null | grep -q "$package_name"; then
            is_security="true"
            ((security_count++))
        fi

        updates+=("{\"name\":\"${package_name}\",\"current_version\":\"${current_version}\",\"available_version\":\"${new_version}\",\"architecture\":\"${arch}\",\"repository\":\"${repository}\",\"is_security\":${is_security}}")
        ((total++))

    done <<< "$check_output"

    echo "{"
    echo "  \"total\": ${total},"
    echo "  \"security\": ${security_count},"
    echo "  \"packages\": ["

    local first=true
    for pkg in "${updates[@]}"; do
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    ${pkg}"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# List only security updates
dnf_list_security_updates() {
    log_debug "Listing security updates..."

    local updates=()
    local total=0

    # Use updateinfo for security updates
    local security_output
    security_output=$($PKG_MGR_CMD updateinfo list --security 2>/dev/null) || true

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^Last\ metadata ]] && continue

        # Parse advisory info: ADVISORY-ID  severity  package-version.arch
        local parts
        read -ra parts <<< "$line"

        [[ ${#parts[@]} -lt 3 ]] && continue

        local advisory="${parts[0]}"
        local severity="${parts[1]}"
        local full_name="${parts[2]}"

        # Split package name and version
        local package_name new_version arch
        if [[ "$full_name" =~ ^(.+)-([0-9][^-]*-[^.]+)\.([^.]+)$ ]]; then
            package_name="${BASH_REMATCH[1]}"
            new_version="${BASH_REMATCH[2]}"
            arch="${BASH_REMATCH[3]}"
        else
            continue
        fi

        local current_version
        current_version=$($RPM -q --qf '%{VERSION}-%{RELEASE}' "$package_name" 2>/dev/null || echo "unknown")

        updates+=("{\"name\":\"${package_name}\",\"current_version\":\"${current_version}\",\"available_version\":\"${new_version}\",\"architecture\":\"${arch}\",\"advisory\":\"${advisory}\",\"severity\":\"${severity}\",\"is_security\":true}")
        ((total++))

    done <<< "$security_output"

    echo "{"
    echo "  \"total\": ${total},"
    echo "  \"security\": ${total},"
    echo "  \"packages\": ["

    local first=true
    for pkg in "${updates[@]}"; do
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    ${pkg}"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# List installed packages
dnf_list_installed() {
    log_debug "Listing installed packages..."

    local packages=()
    local total=0

    while IFS= read -r line; do
        local name version arch
        read -r name version arch <<< "$line"
        packages+=("{\"name\":\"${name}\",\"version\":\"${version}\",\"architecture\":\"${arch}\"}")
        ((total++))
    done < <($RPM -qa --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n' 2>/dev/null)

    echo "{"
    echo "  \"total\": ${total},"
    echo "  \"packages\": ["

    local first=true
    for pkg in "${packages[@]}"; do
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    ${pkg}"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# =============================================================================
# PACKAGE INSTALLATION
# =============================================================================

# Install all available updates
dnf_install_all_updates() {
    log_info "Installing all available updates with ${PKG_MGR}..."

    local start_time
    start_time=$(date +%s)

    local output
    local exit_code=0

    if output=$($PKG_MGR_CMD upgrade -y 2>&1); then
        log_info "All updates installed successfully"
    else
        exit_code=$?
        log_error "Failed to install updates: exit code ${exit_code}"
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Parse installed packages from output
    local installed=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^Upgrading:?[[:space:]]+([^[:space:]]+) ]]; then
            installed+=("{\"name\":\"${BASH_REMATCH[1]}\"}")
        elif [[ "$line" =~ ^Installing:?[[:space:]]+([^[:space:]]+) ]]; then
            installed+=("{\"name\":\"${BASH_REMATCH[1]}\"}")
        fi
    done <<< "$output"

    local status="success"
    [[ $exit_code -ne 0 ]] && status="failure"

    echo "{"
    echo "  \"status\": \"${status}\","
    echo "  \"exit_code\": ${exit_code},"
    echo "  \"duration_seconds\": ${duration},"
    echo "  \"packages_updated\": ["

    local first=true
    for pkg in "${installed[@]}"; do
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    ${pkg}"
    done

    echo ""
    echo "  ],"
    echo "  \"output\": $(json_string "$output")"
    echo "}"

    return $exit_code
}

# Install security updates only
dnf_install_security_updates() {
    log_info "Installing security updates with ${PKG_MGR}..."

    local start_time
    start_time=$(date +%s)

    local output
    local exit_code=0

    if output=$($PKG_MGR_CMD upgrade -y --security 2>&1); then
        log_info "Security updates installed successfully"
    else
        exit_code=$?
        log_error "Failed to install security updates: exit code ${exit_code}"
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    local status="success"
    [[ $exit_code -ne 0 ]] && status="failure"

    echo "{"
    echo "  \"status\": \"${status}\","
    echo "  \"exit_code\": ${exit_code},"
    echo "  \"duration_seconds\": ${duration},"
    echo "  \"output\": $(json_string "$output")"
    echo "}"

    return $exit_code
}

# Install specific package(s)
dnf_install_package() {
    local packages=("$@")

    log_info "Installing packages: ${packages[*]}"

    local output
    local exit_code=0

    if output=$($PKG_MGR_CMD install -y "${packages[@]}" 2>&1); then
        log_info "Packages installed successfully"
    else
        exit_code=$?
        log_error "Failed to install packages"
    fi

    local status="success"
    [[ $exit_code -ne 0 ]] && status="failure"

    echo "{"
    echo "  \"status\": \"${status}\","
    echo "  \"exit_code\": ${exit_code},"
    echo "  \"packages\": [$(printf '"%s",' "${packages[@]}" | sed 's/,$//')],"
    echo "  \"output\": $(json_string "$output")"
    echo "}"

    return $exit_code
}

# =============================================================================
# REBOOT DETECTION
# =============================================================================

# Check if reboot is required
# RHEL/CentOS uses needs-restarting command
dnf_check_reboot_required() {
    log_debug "Checking if reboot is required..."

    local reboot_required="false"
    local reasons=()

    # Use needs-restarting if available (from yum-utils/dnf-utils)
    if command_exists needs-restarting; then
        # -r checks if full reboot is required (kernel update, etc.)
        if ! needs-restarting -r &>/dev/null; then
            reboot_required="true"
            reasons+=("Kernel or core library update pending")
        fi
    fi

    # Also check if running kernel differs from installed
    local running_kernel installed_kernel
    running_kernel=$(uname -r)
    installed_kernel=$($RPM -q kernel --last 2>/dev/null | head -1 | awk '{print $1}' | sed 's/kernel-//')

    if [[ -n "$installed_kernel" ]] && [[ "$running_kernel" != "$installed_kernel" ]]; then
        reboot_required="true"
        reasons+=("Running kernel (${running_kernel}) differs from installed (${installed_kernel})")
    fi

    echo "{"
    echo "  \"reboot_required\": ${reboot_required},"
    echo "  \"reasons\": ["

    local first=true
    for reason in "${reasons[@]}"; do
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    $(json_string "$reason")"
    done

    echo ""
    echo "  ]"
    echo "}"

    [[ "$reboot_required" == "true" ]]
}

# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================

# Get list of services that need restart
dnf_services_to_restart() {
    log_debug "Checking services that need restart..."

    local services=()

    # Use needs-restarting -s if available
    if command_exists needs-restarting; then
        while IFS= read -r service; do
            [[ -n "$service" ]] && services+=("$service")
        done < <(needs-restarting -s 2>/dev/null || true)
    fi

    echo "{"
    echo "  \"services\": ["

    local first=true
    for svc in "${services[@]}"; do
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    $(json_string "$svc")"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# =============================================================================
# PACKAGE INFO
# =============================================================================

# Get information about a specific package
dnf_package_info() {
    local package="$1"

    log_debug "Getting info for package: ${package}"

    local installed_version=""
    local available_version=""
    local is_installed="false"
    local description=""

    # Get installed version
    if installed_version=$($RPM -q --qf '%{VERSION}-%{RELEASE}' "$package" 2>/dev/null); then
        is_installed="true"
    else
        installed_version=""
    fi

    # Get available version
    local pkg_info
    pkg_info=$($PKG_MGR_CMD info "$package" 2>/dev/null || true)

    if [[ -n "$pkg_info" ]]; then
        available_version=$(echo "$pkg_info" | grep "^Version" | head -1 | awk '{print $3}')
        description=$(echo "$pkg_info" | grep "^Summary" | head -1 | cut -d: -f2- | xargs)
    fi

    echo "{"
    echo "  \"name\": $(json_string "$package"),"
    echo "  \"installed\": ${is_installed},"
    echo "  \"installed_version\": $(json_string "$installed_version"),"
    echo "  \"available_version\": $(json_string "$available_version"),"
    echo "  \"description\": $(json_string "$description")"
    echo "}"
}

# =============================================================================
# CLEANUP
# =============================================================================

# Clean up package cache
dnf_cleanup() {
    log_info "Cleaning up ${PKG_MGR} cache..."

    $PKG_MGR_CMD clean all 2>/dev/null || true
    $PKG_MGR_CMD autoremove -y 2>/dev/null || true

    log_info "${PKG_MGR} cleanup completed"
    echo '{"status": "success", "message": "'"${PKG_MGR}"' cleanup completed"}'
}

# =============================================================================
# ROLLBACK (DNF specific)
# =============================================================================

# List transaction history
dnf_history_list() {
    log_debug "Listing ${PKG_MGR} transaction history..."

    $PKG_MGR_CMD history list 2>/dev/null | head -20
}

# Rollback to a specific transaction
dnf_rollback() {
    local transaction_id="$1"

    log_info "Rolling back to transaction ${transaction_id}..."

    if [[ "$PKG_MGR" != "dnf" ]]; then
        log_error "Rollback only supported with DNF"
        echo '{"status": "error", "message": "Rollback only supported with DNF"}'
        return 1
    fi

    local output
    local exit_code=0

    if output=$($PKG_MGR_CMD history rollback "$transaction_id" -y 2>&1); then
        log_info "Rollback completed successfully"
    else
        exit_code=$?
        log_error "Rollback failed"
    fi

    local status="success"
    [[ $exit_code -ne 0 ]] && status="failure"

    echo "{"
    echo "  \"status\": \"${status}\","
    echo "  \"transaction_id\": ${transaction_id},"
    echo "  \"output\": $(json_string "$output")"
    echo "}"

    return $exit_code
}
