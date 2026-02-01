#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - Check Reboot Status
# =============================================================================
# Check if system requires a reboot
# Usage: check-reboot.sh [OPTIONS]
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
LINKSAFE Patch Management - Check Reboot Status

Usage: $(basename "$0") [OPTIONS]

Options:
    --services    Also list services that need restart
    --quiet       Minimal output (exit code only)
    -h, --help    Show this help message

Exit codes:
    0 - Reboot NOT required
    1 - Reboot IS required
    2 - Error occurred

Output: JSON containing reboot status

Examples:
    $(basename "$0")            # Check reboot status
    $(basename "$0") --services # Include services needing restart
EOF
    exit 0
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    local show_services=false
    local quiet=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --services)
                show_services=true
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
        [[ "$quiet" != "true" ]] && json_error "Unsupported operating system: ${OS_ID}"
        exit 2
    fi

    # Source package manager library
    if ! source_package_manager_lib; then
        [[ "$quiet" != "true" ]] && json_error "Failed to load package manager library"
        exit 2
    fi

    [[ "$quiet" != "true" ]] && log_debug "Checking reboot status..."

    local reboot_json
    local services_json='{"services": []}'
    local reboot_required="false"

    # Check reboot status
    case "$PACKAGE_MANAGER" in
        apt)
            reboot_json=$(apt_check_reboot_required 2>/dev/null) || reboot_json='{"reboot_required": false, "reasons": []}'
            if [[ "$show_services" == "true" ]]; then
                services_json=$(apt_services_to_restart 2>/dev/null) || services_json='{"services": []}'
            fi
            ;;
        dnf|yum)
            reboot_json=$(dnf_check_reboot_required 2>/dev/null) || reboot_json='{"reboot_required": false, "reasons": []}'
            if [[ "$show_services" == "true" ]]; then
                services_json=$(dnf_services_to_restart 2>/dev/null) || services_json='{"services": []}'
            fi
            ;;
        zypper)
            reboot_json=$(zypper_check_reboot_required 2>/dev/null) || reboot_json='{"reboot_required": false, "reasons": []}'
            if [[ "$show_services" == "true" ]]; then
                services_json=$(zypper_services_to_restart 2>/dev/null) || services_json='{"services": []}'
            fi
            ;;
        *)
            [[ "$quiet" != "true" ]] && json_error "Unsupported package manager: ${PACKAGE_MANAGER}"
            exit 2
            ;;
    esac

    # Extract reboot status
    if echo "$reboot_json" | grep -q '"reboot_required": true'; then
        reboot_required="true"
    fi

    # Also check our own pending reboot flag
    if is_reboot_pending; then
        reboot_required="true"
    fi

    # Extract reasons array
    local reasons
    reasons=$(echo "$reboot_json" | sed -n '/"reasons":/,/]/p' | tail -n +2 | head -n -1 || echo "")

    # Extract services array
    local services
    services=$(echo "$services_json" | sed -n '/"services":/,/]/p' | tail -n +2 | head -n -1 || echo "")

    # Build output
    local hostname
    hostname=$(get_hostname)
    local timestamp
    timestamp=$(get_timestamp)

    if [[ "$quiet" != "true" ]]; then
        cat <<EOF
{
  "hostname": "${hostname}",
  "timestamp": "${timestamp}",
  "reboot_required": ${reboot_required},
  "reasons": [${reasons}
  ],
  "services_to_restart": [${services}
  ],
  "os": $(os_info_json)
}
EOF
    fi

    # Return exit code based on reboot status
    if [[ "$reboot_required" == "true" ]]; then
        [[ "$quiet" != "true" ]] && log_info "Reboot IS required"
        exit 1
    else
        [[ "$quiet" != "true" ]] && log_info "Reboot NOT required"
        exit 0
    fi
}

# Run main
main "$@"
