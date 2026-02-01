#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - APT Package Manager Library
# =============================================================================
# APT implementation for Debian/Ubuntu based systems
# Reference: Rudder apt.rs implementation
# =============================================================================

# Source common library if not already sourced
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/../lib"
if [[ -z "${LINKSAFE_PATCH_VERSION:-}" ]]; then
    source "${LIB_DIR}/common.sh"
fi

# =============================================================================
# APT CONFIGURATION
# =============================================================================
readonly APT_GET="apt-get"
readonly APT_CACHE="apt-cache"
readonly APT_LIST="apt"
readonly DPKG="dpkg"
readonly DPKG_QUERY="dpkg-query"

# Environment for non-interactive operation
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

# =============================================================================
# CACHE MANAGEMENT
# =============================================================================

# Update package cache
apt_update_cache() {
    log_info "Updating APT package cache..."

    local output
    if output=$($APT_GET update -qq 2>&1); then
        log_info "APT cache updated successfully"
        return 0
    else
        log_error "Failed to update APT cache: ${output}"
        return 1
    fi
}

# =============================================================================
# PACKAGE LISTING
# =============================================================================

# Check if a package update is from security repository
# Uses apt-cache policy to check origin
apt_is_security_update() {
    local package="$1"
    local version="$2"

    # Method 1: Check apt-cache policy for security origin
    local policy_output
    policy_output=$($APT_CACHE policy "$package" 2>/dev/null)

    # Look for the candidate version and check if it's from security
    if echo "$policy_output" | grep -A1 "Candidate:" | grep -qi "security"; then
        return 0
    fi

    # Method 2: Check version table for security origin
    # Format: version priority table
    #    500 http://security.ubuntu.com/ubuntu jammy-security/main
    if echo "$policy_output" | grep -E "^\s+[0-9]+\s+" | grep -qi "security"; then
        # Check if the candidate version is from security
        local candidate
        candidate=$(echo "$policy_output" | grep "Candidate:" | awk '{print $2}')
        if [[ "$candidate" == "$version" ]]; then
            if echo "$policy_output" | grep "$version" | grep -qi "security"; then
                return 0
            fi
        fi
    fi

    return 1
}

# List all available updates
# Output: JSON array of packages
apt_list_updates() {
    log_debug "Listing available APT updates..."

    local updates=()
    local total=0
    local security_count=0

    # Get upgradable packages
    while IFS= read -r line; do
        # Skip header line "Listing..."
        [[ "$line" == "Listing..."* ]] && continue
        [[ -z "$line" ]] && continue

        # Parse line: package/source version arch [upgradable from: old_version]
        local package_full=${line%%/*}
        local rest=${line#*/}
        local source=${rest%% *}
        rest=${rest#* }
        local new_version=${rest%% *}
        rest=${rest#* }
        local arch=${rest%% *}

        # Extract current version from [upgradable from: X.X.X]
        local current_version=""
        local upgradable_regex='\[upgradable from: ([^]]+)\]'
        if [[ "$line" =~ $upgradable_regex ]]; then
            current_version="${BASH_REMATCH[1]}"
        fi

        # Check if security update using multiple methods
        local is_security="false"

        # Method 1: Check source field (handles comma-separated repos like "jammy-updates,jammy-security")
        if [[ "$source" == *"-security"* ]] || [[ "$source" == *"/security"* ]]; then
            is_security="true"
        fi

        # Method 2: Use apt-cache policy for more accurate detection
        if [[ "$is_security" == "false" ]]; then
            if apt_is_security_update "$package_full" "$new_version"; then
                is_security="true"
            fi
        fi

        if [[ "$is_security" == "true" ]]; then
            ((security_count++))
        fi

        updates+=("{\"name\":\"${package_full}\",\"current_version\":\"${current_version}\",\"available_version\":\"${new_version}\",\"architecture\":\"${arch}\",\"repository\":\"${source}\",\"is_security\":${is_security}}")
        ((total++))

    done < <($APT_LIST list --upgradable 2>/dev/null)

    # Output JSON
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
apt_list_security_updates() {
    log_debug "Listing security updates..."

    local updates=()
    local total=0

    while IFS= read -r line; do
        [[ "$line" == "Listing..."* ]] && continue
        [[ -z "$line" ]] && continue

        local package_full=${line%%/*}
        local rest=${line#*/}
        local source=${rest%% *}
        rest=${rest#* }
        local new_version=${rest%% *}
        rest=${rest#* }
        local arch=${rest%% *}

        local current_version=""
        local upgradable_regex2='\[upgradable from: ([^]]+)\]'
        if [[ "$line" =~ $upgradable_regex2 ]]; then
            current_version="${BASH_REMATCH[1]}"
        fi

        # Check if security update using multiple methods
        local is_security="false"

        # Method 1: Check source field
        if [[ "$source" == *"-security"* ]] || [[ "$source" == *"/security"* ]]; then
            is_security="true"
        fi

        # Method 2: Use apt-cache policy
        if [[ "$is_security" == "false" ]]; then
            if apt_is_security_update "$package_full" "$new_version"; then
                is_security="true"
            fi
        fi

        # Only include if security
        if [[ "$is_security" == "true" ]]; then
            updates+=("{\"name\":\"${package_full}\",\"current_version\":\"${current_version}\",\"available_version\":\"${new_version}\",\"architecture\":\"${arch}\",\"repository\":\"${source}\",\"is_security\":true}")
            ((total++))
        fi
    done < <($APT_LIST list --upgradable 2>/dev/null)

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
apt_list_installed() {
    log_debug "Listing installed packages..."

    local packages=()
    local total=0

    while IFS= read -r line; do
        # Format: package\tversion\tarchitecture
        local package version arch
        IFS=$'\t' read -r package version arch <<< "$line"
        packages+=("{\"name\":\"${package}\",\"version\":\"${version}\",\"architecture\":\"${arch}\"}")
        ((total++))
    done < <($DPKG_QUERY -W -f='${Package}\t${Version}\t${Architecture}\n' 2>/dev/null)

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
apt_install_all_updates() {
    log_info "Installing all available updates..."

    local start_time
    start_time=$(date +%s)

    local output
    local exit_code=0

    # Run upgrade
    if output=$($APT_GET upgrade -y -o Dpkg::Options::="--force-confold" 2>&1); then
        log_info "All updates installed successfully"
    else
        exit_code=$?
        log_error "Failed to install updates: ${output}"
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Parse installed packages from output
    local installed=()
    # Store regex in variable to avoid bash parsing issues with parentheses
    local unpack_regex='^Unpacking ([^ ]+) \(([^)]+)\)'
    while IFS= read -r line; do
        if [[ "$line" =~ $unpack_regex ]]; then
            local pkg="${BASH_REMATCH[1]}"
            local ver="${BASH_REMATCH[2]}"
            installed+=("{\"name\":\"${pkg}\",\"version\":\"${ver}\"}")
        fi
    done <<< "$output"

    # Output result JSON
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
apt_install_security_updates() {
    log_info "Installing security updates only..."

    local start_time
    start_time=$(date +%s)

    # Use unattended-upgrades if available for proper security-only updates
    if command_exists unattended-upgrade; then
        log_debug "Using unattended-upgrade for security updates"
        local output
        local exit_code=0

        if output=$(unattended-upgrade -d 2>&1); then
            log_info "Security updates installed via unattended-upgrade"
        else
            exit_code=$?
            log_warn "unattended-upgrade returned: ${exit_code}"
        fi

        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))

        local status="success"
        [[ $exit_code -ne 0 ]] && status="partial"

        echo "{"
        echo "  \"status\": \"${status}\","
        echo "  \"method\": \"unattended-upgrade\","
        echo "  \"duration_seconds\": ${duration},"
        echo "  \"output\": $(json_string "$output")"
        echo "}"

        return $exit_code
    fi

    # Fallback: manually filter and install security packages
    log_debug "Falling back to manual security update installation"

    local security_pkgs=()
    while IFS= read -r line; do
        [[ "$line" == "Listing..."* ]] && continue
        [[ -z "$line" ]] && continue

        if [[ "$line" == *"security"* ]]; then
            local pkg=${line%%/*}
            security_pkgs+=("$pkg")
        fi
    done < <($APT_LIST list --upgradable 2>/dev/null)

    if [[ ${#security_pkgs[@]} -eq 0 ]]; then
        log_info "No security updates available"
        echo '{"status": "success", "message": "No security updates available", "packages_updated": []}'
        return 0
    fi

    local output
    local exit_code=0

    if output=$($APT_GET install -y -o Dpkg::Options::="--force-confold" "${security_pkgs[@]}" 2>&1); then
        log_info "Security updates installed successfully"
    else
        exit_code=$?
        log_error "Failed to install security updates"
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    local status="success"
    [[ $exit_code -ne 0 ]] && status="failure"

    echo "{"
    echo "  \"status\": \"${status}\","
    echo "  \"method\": \"manual\","
    echo "  \"duration_seconds\": ${duration},"
    echo "  \"packages_requested\": ${#security_pkgs[@]},"
    echo "  \"output\": $(json_string "$output")"
    echo "}"

    return $exit_code
}

# Install specific package(s)
apt_install_package() {
    local packages=("$@")

    log_info "Installing packages: ${packages[*]}"

    local output
    local exit_code=0

    if output=$($APT_GET install -y -o Dpkg::Options::="--force-confold" "${packages[@]}" 2>&1); then
        log_info "Packages installed successfully"
    else
        exit_code=$?
        log_error "Failed to install packages: ${output}"
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
# Debian/Ubuntu uses /var/run/reboot-required file
apt_check_reboot_required() {
    log_debug "Checking if reboot is required..."

    local reboot_required="false"
    local reasons=()

    # Check reboot-required file
    if [[ -f /var/run/reboot-required ]]; then
        reboot_required="true"
        reasons+=("reboot-required file exists")

        # Get list of packages that require reboot
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            while IFS= read -r pkg; do
                reasons+=("Package: ${pkg}")
            done < /var/run/reboot-required.pkgs
        fi
    fi

    # Also check using needrestart if available
    if command_exists needrestart; then
        local needrestart_output
        needrestart_output=$(needrestart -b 2>/dev/null || true)

        if [[ "$needrestart_output" == *"NEEDRESTART-KSTA: 3"* ]]; then
            reboot_required="true"
            reasons+=("Kernel update pending (needrestart)")
        fi
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
apt_services_to_restart() {
    log_debug "Checking services that need restart..."

    local services=()

    # Use needrestart if available
    local needrestart_regex='^NEEDRESTART-SVC: (.+)$'
    if command_exists needrestart; then
        while IFS= read -r line; do
            if [[ "$line" =~ $needrestart_regex ]]; then
                services+=("${BASH_REMATCH[1]}")
            fi
        done < <(needrestart -b 2>/dev/null || true)
    fi

    # Alternative: use checkrestart from debian-goodies
    local checkrestart_regex='service ([^ ]+) '
    if [[ ${#services[@]} -eq 0 ]] && command_exists checkrestart; then
        while IFS= read -r line; do
            if [[ "$line" =~ $checkrestart_regex ]]; then
                services+=("${BASH_REMATCH[1]}")
            fi
        done < <(checkrestart 2>/dev/null || true)
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
apt_package_info() {
    local package="$1"

    log_debug "Getting info for package: ${package}"

    local installed_version=""
    local available_version=""
    local is_installed="false"
    local description=""

    # Get installed version
    if installed_version=$($DPKG_QUERY -W -f='${Version}' "$package" 2>/dev/null); then
        is_installed="true"
    fi

    # Get available version and description
    local apt_output
    apt_output=$($APT_CACHE show "$package" 2>/dev/null | head -50)

    if [[ -n "$apt_output" ]]; then
        available_version=$(echo "$apt_output" | grep "^Version:" | head -1 | awk '{print $2}')
        description=$(echo "$apt_output" | grep "^Description:" | head -1 | cut -d: -f2- | xargs)
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
apt_cleanup() {
    log_info "Cleaning up APT cache..."

    $APT_GET clean 2>/dev/null || true
    $APT_GET autoclean 2>/dev/null || true
    $APT_GET autoremove -y 2>/dev/null || true

    log_info "APT cleanup completed"
    echo '{"status": "success", "message": "APT cleanup completed"}'
}
