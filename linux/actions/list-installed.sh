#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - List Installed Packages
# =============================================================================
# List all installed packages on the system
# Usage: list-installed.sh [OPTIONS]
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
LINKSAFE Patch Management - List Installed Packages

Usage: $(basename "$0") [OPTIONS]

Options:
    --filter PATTERN  Filter packages by name pattern
    --limit N         Limit output to N packages
    --quiet           Minimal output
    -h, --help        Show this help message

Output: JSON containing installed packages

Examples:
    $(basename "$0")                    # List all packages
    $(basename "$0") --filter openssl   # Filter by name
    $(basename "$0") --limit 100        # Limit to 100 packages
EOF
    exit 0
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    local filter=""
    local limit=0
    local quiet=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --filter)
                filter="$2"
                shift 2
                ;;
            --limit)
                limit="$2"
                shift 2
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
        json_error "Unsupported operating system: ${OS_ID}"
        exit 1
    fi

    # Source package manager library
    if ! source_package_manager_lib; then
        json_error "Failed to load package manager library"
        exit 1
    fi

    [[ "$quiet" != "true" ]] && log_info "Listing installed packages..."

    local installed_json

    # Get installed packages
    case "$PACKAGE_MANAGER" in
        apt)
            installed_json=$(apt_list_installed)
            ;;
        dnf|yum)
            installed_json=$(dnf_list_installed)
            ;;
        zypper)
            installed_json=$(zypper_list_installed)
            ;;
        *)
            json_error "Unsupported package manager: ${PACKAGE_MANAGER}"
            exit 1
            ;;
    esac

    # Apply filter if specified
    if [[ -n "$filter" ]]; then
        # Filter packages by name
        local filtered_packages
        filtered_packages=$(echo "$installed_json" | grep -i "\"name\":\"[^\"]*${filter}[^\"]*\"" || echo "")

        if [[ -n "$filtered_packages" ]]; then
            local count
            count=$(echo "$filtered_packages" | wc -l)

            echo "{"
            echo "  \"total\": ${count},"
            echo "  \"filter\": \"${filter}\","
            echo "  \"packages\": ["

            local first=true
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                [[ "$first" != "true" ]] && echo ","
                first=false
                echo -n "    ${line}"
            done <<< "$filtered_packages"

            echo ""
            echo "  ]"
            echo "}"
        else
            echo '{"total": 0, "filter": "'"${filter}"'", "packages": []}'
        fi
    elif [[ "$limit" -gt 0 ]]; then
        # Apply limit
        echo "$installed_json" | head -n $((limit + 10)) | sed "s/\"total\": [0-9]*/\"total\": ${limit}/"
    else
        # Output as-is
        echo "$installed_json"
    fi

    local total
    total=$(echo "$installed_json" | grep -o '"total": [0-9]*' | grep -o '[0-9]*' || echo "0")
    [[ "$quiet" != "true" ]] && log_info "Found ${total} installed packages"
}

# Run main
main "$@"
