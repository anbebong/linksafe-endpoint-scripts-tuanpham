#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - Rollback Action
# =============================================================================
# Rollback to previous package state (where supported)
# Usage: rollback.sh [OPTIONS]
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
LINKSAFE Patch Management - Rollback

Usage: $(basename "$0") [OPTIONS]

Options:
    --list             List available rollback points
    --transaction ID   Rollback to specific DNF transaction (RHEL)
    --snapshot ID      Rollback to specific snapper snapshot (SUSE)
    --package PKG VER  Downgrade specific package to version
    -h, --help         Show this help message

Supported rollback methods:
    - DNF: Transaction rollback (RHEL/CentOS/Fedora)
    - Zypper: Snapper snapshot rollback (SUSE)
    - APT: Package downgrade only (Debian/Ubuntu)

Examples:
    $(basename "$0") --list                    # List rollback points
    $(basename "$0") --transaction 45          # Rollback to DNF transaction 45
    $(basename "$0") --snapshot 10             # Rollback to snapshot 10
    $(basename "$0") --package nginx 1.18.0    # Downgrade nginx to 1.18.0
EOF
    exit 0
}

# =============================================================================
# ROLLBACK FUNCTIONS
# =============================================================================

# List available rollback points
list_rollback_points() {
    log_info "Listing available rollback points..."

    case "$PACKAGE_MANAGER" in
        dnf)
            echo "{"
            echo "  \"type\": \"dnf_transactions\","
            echo "  \"transactions\": ["

            local first=true
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                [[ "$line" =~ ^ID ]] && continue
                [[ "$line" =~ ^-+ ]] && continue

                local id action date_time altered
                read -r id action date_time altered <<< "$line"

                [[ -z "$id" ]] && continue

                [[ "$first" != "true" ]] && echo ","
                first=false
                echo -n "    {\"id\": ${id}, \"action\": \"${action}\", \"date\": \"${date_time}\"}"
            done < <(dnf history list 2>/dev/null | head -20)

            echo ""
            echo "  ]"
            echo "}"
            ;;

        yum)
            echo "{"
            echo "  \"type\": \"yum_transactions\","
            echo "  \"message\": \"YUM transaction rollback supported via 'yum history undo'\","
            echo "  \"transactions\": []"
            echo "}"
            ;;

        zypper)
            if command_exists snapper; then
                echo "{"
                echo "  \"type\": \"snapper_snapshots\","
                echo "  \"snapshots\": ["

                local first=true
                while IFS='|' read -r id type pre date user cleanup desc; do
                    [[ -z "$id" ]] && continue
                    [[ "$id" =~ ^# ]] && continue
                    [[ "$id" =~ ^-+ ]] && continue

                    id=$(trim "$id")
                    type=$(trim "$type")
                    date=$(trim "$date")
                    desc=$(trim "$desc")

                    [[ -z "$id" ]] || [[ "$id" == "0" ]] && continue

                    [[ "$first" != "true" ]] && echo ","
                    first=false
                    echo -n "    {\"id\": ${id}, \"type\": \"${type}\", \"date\": \"${date}\", \"description\": \"${desc}\"}"
                done < <(snapper list 2>/dev/null | head -20)

                echo ""
                echo "  ]"
                echo "}"
            else
                echo '{"type": "none", "message": "Snapper not available on this SUSE system"}'
            fi
            ;;

        apt)
            echo "{"
            echo "  \"type\": \"apt_downgrade\","
            echo "  \"message\": \"APT does not support transaction rollback. Use --package to downgrade specific packages.\","
            echo "  \"available_versions\": []"
            echo "}"
            ;;

        *)
            json_error "Rollback not supported for package manager: ${PACKAGE_MANAGER}"
            return 1
            ;;
    esac
}

# Rollback DNF transaction
rollback_dnf_transaction() {
    local transaction_id="$1"

    log_info "Rolling back to DNF transaction ${transaction_id}..."

    if [[ "$PACKAGE_MANAGER" != "dnf" ]]; then
        json_error "DNF transaction rollback only available on DNF systems"
        return 1
    fi

    # Source DNF library
    source_package_manager_lib

    dnf_rollback "$transaction_id"
}

# Rollback snapper snapshot
rollback_snapshot() {
    local snapshot_id="$1"

    log_info "Rolling back to snapshot ${snapshot_id}..."

    if [[ "$PACKAGE_MANAGER" != "zypper" ]]; then
        json_error "Snapshot rollback only available on SUSE/Zypper systems"
        return 1
    fi

    # Source Zypper library
    source_package_manager_lib

    zypper_rollback_snapshot "$snapshot_id"
}

# Downgrade specific package
downgrade_package() {
    local package="$1"
    local version="$2"

    log_info "Downgrading ${package} to version ${version}..."

    check_root

    local output
    local exit_code=0

    case "$PACKAGE_MANAGER" in
        apt)
            if output=$(apt-get install -y "${package}=${version}" 2>&1); then
                log_info "Package downgraded successfully"
            else
                exit_code=$?
                log_error "Failed to downgrade package"
            fi
            ;;
        dnf|yum)
            if output=$(dnf downgrade -y "${package}-${version}" 2>&1); then
                log_info "Package downgraded successfully"
            else
                exit_code=$?
                log_error "Failed to downgrade package"
            fi
            ;;
        zypper)
            if output=$(zypper install -y --oldpackage "${package}=${version}" 2>&1); then
                log_info "Package downgraded successfully"
            else
                exit_code=$?
                log_error "Failed to downgrade package"
            fi
            ;;
        *)
            json_error "Downgrade not supported for: ${PACKAGE_MANAGER}"
            return 1
            ;;
    esac

    local status="success"
    [[ $exit_code -ne 0 ]] && status="failure"

    echo "{"
    echo "  \"status\": \"${status}\","
    echo "  \"package\": \"${package}\","
    echo "  \"target_version\": \"${version}\","
    echo "  \"output\": $(json_string "$output")"
    echo "}"

    return $exit_code
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    local action=""
    local transaction_id=""
    local snapshot_id=""
    local package=""
    local version=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list)
                action="list"
                shift
                ;;
            --transaction)
                action="transaction"
                transaction_id="$2"
                shift 2
                ;;
            --snapshot)
                action="snapshot"
                snapshot_id="$2"
                shift 2
                ;;
            --package)
                action="downgrade"
                package="$2"
                version="$3"
                shift 3
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

    # Default action
    [[ -z "$action" ]] && action="list"

    # Check if OS is supported
    if ! is_os_supported; then
        json_error "Unsupported operating system: ${OS_ID}"
        exit 1
    fi

    # Execute action
    case "$action" in
        list)
            list_rollback_points
            ;;
        transaction)
            rollback_dnf_transaction "$transaction_id"
            ;;
        snapshot)
            rollback_snapshot "$snapshot_id"
            ;;
        downgrade)
            if [[ -z "$package" ]] || [[ -z "$version" ]]; then
                json_error "Package name and version required for downgrade"
                exit 1
            fi
            downgrade_package "$package" "$version"
            ;;
        *)
            json_error "Unknown action: ${action}"
            exit 1
            ;;
    esac
}

# Run main
main "$@"
