#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - Check Updates Action
# =============================================================================
# List available updates for the system
# Usage: check-updates.sh [--security-only] [--refresh]
# =============================================================================

set -euo pipefail

# Get script directory (resolve symlinks)
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Source libraries
source "${BASE_DIR}/lib/common.sh"
source "${BASE_DIR}/lib/os-detect.sh"

# =============================================================================
# USAGE
# =============================================================================
usage() {
    cat <<EOF
LINKSAFE Patch Management - Check Updates

Usage: $(basename "$0") [OPTIONS]

Options:
    --security-only    Only list security updates
    --refresh          Force refresh package cache before checking
    --save             Save result to state file
    --quiet            Minimal output (JSON only)
    -h, --help         Show this help message

Output: JSON containing available updates

Examples:
    $(basename "$0")                    # List all updates
    $(basename "$0") --security-only    # List security updates only
    $(basename "$0") --refresh --save   # Refresh cache and save result
EOF
    exit 0
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    local security_only=false
    local refresh=false
    local save_result=false
    local quiet=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --security-only)
                security_only=true
                shift
                ;;
            --refresh)
                refresh=true
                shift
                ;;
            --save)
                save_result=true
                shift
                ;;
            --quiet)
                quiet=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Check if OS is supported
    if ! is_os_supported; then
        json_error "Unsupported operating system: ${OS_ID} (${PACKAGE_MANAGER})"
        exit 1
    fi

    # Source package manager library
    if ! source_package_manager_lib; then
        json_error "Failed to load package manager library"
        exit 1
    fi

    [[ "$quiet" != "true" ]] && log_info "Checking for updates on ${OS_PRETTY_NAME}..."

    # Refresh cache if requested
    if [[ "$refresh" == "true" ]]; then
        [[ "$quiet" != "true" ]] && log_info "Refreshing package cache..."
        case "$PACKAGE_MANAGER" in
            apt)    apt_update_cache >/dev/null 2>&1 || true ;;
            dnf|yum) dnf_update_cache >/dev/null 2>&1 || true ;;
            zypper) zypper_update_cache >/dev/null 2>&1 || true ;;
        esac
    fi

    # Get updates
    local updates_json
    local reboot_json

    case "$PACKAGE_MANAGER" in
        apt)
            if [[ "$security_only" == "true" ]]; then
                updates_json=$(apt_list_security_updates)
            else
                updates_json=$(apt_list_updates)
            fi
            reboot_json=$(apt_check_reboot_required 2>/dev/null || echo '{"reboot_required": false}')
            ;;
        dnf|yum)
            if [[ "$security_only" == "true" ]]; then
                updates_json=$(dnf_list_security_updates)
            else
                updates_json=$(dnf_list_updates)
            fi
            reboot_json=$(dnf_check_reboot_required 2>/dev/null || echo '{"reboot_required": false}')
            ;;
        zypper)
            if [[ "$security_only" == "true" ]]; then
                updates_json=$(zypper_list_security_updates)
            else
                updates_json=$(zypper_list_updates)
            fi
            reboot_json=$(zypper_check_reboot_required 2>/dev/null || echo '{"reboot_required": false}')
            ;;
        *)
            json_error "Unsupported package manager: ${PACKAGE_MANAGER}"
            exit 1
            ;;
    esac

    # Extract reboot status
    local reboot_required="false"
    if echo "$reboot_json" | grep -q '"reboot_required": true'; then
        reboot_required="true"
    fi

    # Build final output
    local hostname
    hostname=$(get_hostname)
    local timestamp
    timestamp=$(get_timestamp)

    # Parse updates data
    local total security packages
    total=$(echo "$updates_json" | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    security=$(echo "$updates_json" | grep -o '"security": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")

    # Extract packages array
    local packages_array
    packages_array=$(echo "$updates_json" | sed -n '/"packages":/,/^[[:space:]]*]/p' | tail -n +2)

    # Final JSON output
    local result
    result=$(cat <<EOF
{
  "hostname": "${hostname}",
  "timestamp": "${timestamp}",
  "os": $(os_info_json),
  "reboot_required": ${reboot_required},
  "updates": {
    "total": ${total},
    "security": ${security},
    "packages": ${packages_array:-[]}
  }
}
EOF
)

    # Save if requested
    if [[ "$save_result" == "true" ]]; then
        save_state "last-check.json" "$result"
        [[ "$quiet" != "true" ]] && log_info "Result saved to state file"
    fi

    # Output result with DATA: prefix (compact JSON on single line)
    local compact_result
    compact_result=$(echo "$result" | tr -d '\n' | sed 's/  */ /g')
    output_data "$compact_result"

    [[ "$quiet" != "true" ]] && log_info "Found ${total} updates (${security} security)"
}

# Run main
main "$@"
