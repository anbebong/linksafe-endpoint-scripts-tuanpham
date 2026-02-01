#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - Zypper Package Manager Library
# =============================================================================
# Zypper implementation for SUSE/SLES/openSUSE
# Reference: Rudder zypper.rs implementation
# =============================================================================

# Source common library if not already sourced
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/../lib"
if [[ -z "${LINKSAFE_PATCH_VERSION:-}" ]]; then
    source "${LIB_DIR}/common.sh"
fi

# =============================================================================
# ZYPPER CONFIGURATION
# =============================================================================
readonly ZYPPER="zypper"
readonly RPM="rpm"

# Non-interactive mode
export ZYPPER_OPTS="--non-interactive --no-gpg-checks"

# =============================================================================
# CACHE MANAGEMENT
# =============================================================================

# Update package cache
zypper_update_cache() {
    log_info "Updating Zypper package cache..."

    local output
    if output=$($ZYPPER $ZYPPER_OPTS refresh 2>&1); then
        log_info "Zypper cache updated successfully"
        return 0
    else
        log_error "Failed to update Zypper cache: ${output}"
        return 1
    fi
}

# =============================================================================
# PACKAGE LISTING
# =============================================================================

# List all available updates
zypper_list_updates() {
    log_debug "Listing available Zypper updates..."

    local updates=()
    local total=0
    local security_count=0

    # Get list of updates
    while IFS='|' read -r status repo name current_ver new_ver arch; do
        # Skip header and empty lines
        [[ -z "$name" ]] && continue
        [[ "$name" =~ ^-+$ ]] && continue
        [[ "$name" == "Name" ]] && continue

        # Trim whitespace
        name=$(trim "$name")
        current_ver=$(trim "$current_ver")
        new_ver=$(trim "$new_ver")
        arch=$(trim "$arch")
        repo=$(trim "$repo")

        [[ -z "$name" ]] && continue

        # Check if security update (would need patch info)
        local is_security="false"

        updates+=("{\"name\":\"${name}\",\"current_version\":\"${current_ver}\",\"available_version\":\"${new_ver}\",\"architecture\":\"${arch}\",\"repository\":\"${repo}\",\"is_security\":${is_security}}")
        ((total++))

    done < <($ZYPPER $ZYPPER_OPTS list-updates 2>/dev/null)

    # Get security patch count
    security_count=$($ZYPPER $ZYPPER_OPTS list-patches --category security 2>/dev/null | grep -c "^[[:space:]]*|" || echo "0")

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

# List only security updates (patches)
zypper_list_security_updates() {
    log_debug "Listing security patches..."

    local patches=()
    local total=0

    while IFS='|' read -r repo name category severity interactive status summary; do
        [[ -z "$name" ]] && continue
        [[ "$name" =~ ^-+$ ]] && continue
        [[ "$name" == "Name" ]] && continue

        name=$(trim "$name")
        category=$(trim "$category")
        severity=$(trim "$severity")
        status=$(trim "$status")
        summary=$(trim "$summary")

        [[ -z "$name" ]] && continue

        patches+=("{\"name\":\"${name}\",\"category\":\"${category}\",\"severity\":\"${severity}\",\"status\":\"${status}\",\"summary\":\"${summary}\",\"is_security\":true}")
        ((total++))

    done < <($ZYPPER $ZYPPER_OPTS list-patches --category security 2>/dev/null)

    echo "{"
    echo "  \"total\": ${total},"
    echo "  \"security\": ${total},"
    echo "  \"patches\": ["

    local first=true
    for patch in "${patches[@]}"; do
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    ${patch}"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# List installed packages
zypper_list_installed() {
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
zypper_install_all_updates() {
    log_info "Installing all available updates with Zypper..."

    local start_time
    start_time=$(date +%s)

    local output
    local exit_code=0

    if output=$($ZYPPER $ZYPPER_OPTS update 2>&1); then
        log_info "All updates installed successfully"
    else
        exit_code=$?
        log_error "Failed to install updates: exit code ${exit_code}"
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

# Install security patches only
zypper_install_security_updates() {
    log_info "Installing security patches with Zypper..."

    local start_time
    start_time=$(date +%s)

    local output
    local exit_code=0

    if output=$($ZYPPER $ZYPPER_OPTS patch --category security 2>&1); then
        log_info "Security patches installed successfully"
    else
        exit_code=$?
        log_error "Failed to install security patches: exit code ${exit_code}"
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
zypper_install_package() {
    local packages=("$@")

    log_info "Installing packages: ${packages[*]}"

    local output
    local exit_code=0

    if output=$($ZYPPER $ZYPPER_OPTS install "${packages[@]}" 2>&1); then
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
# SUSE uses zypper ps to check for processes using deleted files
zypper_check_reboot_required() {
    log_debug "Checking if reboot is required..."

    local reboot_required="false"
    local reasons=()

    # Check zypper needs-rebooting (if available)
    if $ZYPPER $ZYPPER_OPTS needs-rebooting &>/dev/null; then
        # Exit code 0 means reboot needed
        reboot_required="true"
        reasons+=("Zypper indicates reboot required")
    fi

    # Also check running kernel vs installed
    local running_kernel installed_kernel
    running_kernel=$(uname -r)
    installed_kernel=$($RPM -q kernel-default --last 2>/dev/null | head -1 | awk '{print $1}' | sed 's/kernel-default-//')

    if [[ -n "$installed_kernel" ]] && [[ "$running_kernel" != *"$installed_kernel"* ]]; then
        reboot_required="true"
        reasons+=("Running kernel differs from installed kernel")
    fi

    # Check for processes using deleted libraries
    local ps_output
    ps_output=$($ZYPPER $ZYPPER_OPTS ps -s 2>/dev/null || true)
    if [[ -n "$ps_output" ]] && [[ "$ps_output" != *"No processes"* ]]; then
        reboot_required="true"
        reasons+=("Processes using deleted files detected")
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
zypper_services_to_restart() {
    log_debug "Checking services that need restart..."

    local services=()

    # Use zypper ps to find services
    while IFS='|' read -r pid ppid uid user command service; do
        service=$(trim "$service")
        [[ -z "$service" ]] && continue
        [[ "$service" == "Service" ]] && continue
        [[ "$service" =~ ^-+$ ]] && continue

        # Avoid duplicates
        local found=false
        for s in "${services[@]}"; do
            [[ "$s" == "$service" ]] && found=true && break
        done
        [[ "$found" == "false" ]] && services+=("$service")

    done < <($ZYPPER $ZYPPER_OPTS ps -s 2>/dev/null || true)

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
zypper_package_info() {
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
    pkg_info=$($ZYPPER $ZYPPER_OPTS info "$package" 2>/dev/null || true)

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
zypper_cleanup() {
    log_info "Cleaning up Zypper cache..."

    $ZYPPER $ZYPPER_OPTS clean --all 2>/dev/null || true

    log_info "Zypper cleanup completed"
    echo '{"status": "success", "message": "Zypper cleanup completed"}'
}

# =============================================================================
# ROLLBACK
# =============================================================================

# List snapshots (if snapper is available)
zypper_list_snapshots() {
    if command_exists snapper; then
        snapper list 2>/dev/null
    else
        echo "Snapper not available"
    fi
}

# Rollback to snapshot
zypper_rollback_snapshot() {
    local snapshot_id="$1"

    if ! command_exists snapper; then
        log_error "Snapper not available for rollback"
        echo '{"status": "error", "message": "Snapper not available"}'
        return 1
    fi

    log_info "Rolling back to snapshot ${snapshot_id}..."

    local output
    local exit_code=0

    if output=$(snapper rollback "$snapshot_id" 2>&1); then
        log_info "Rollback scheduled (will apply on reboot)"
    else
        exit_code=$?
        log_error "Rollback failed"
    fi

    local status="success"
    [[ $exit_code -ne 0 ]] && status="failure"

    echo "{"
    echo "  \"status\": \"${status}\","
    echo "  \"snapshot_id\": ${snapshot_id},"
    echo "  \"message\": \"Rollback will apply on next reboot\","
    echo "  \"output\": $(json_string "$output")"
    echo "}"

    return $exit_code
}
