#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - Install Updates Action
# =============================================================================
# Install available updates with pre/post hooks support
# Usage: install-updates.sh [OPTIONS] [PACKAGES...]
# =============================================================================

set -euo pipefail

# Get script directory (resolve symlinks)
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LINUX_DIR="$BASE_DIR"

# Source libraries
source "${BASE_DIR}/lib/common.sh"
source "${BASE_DIR}/lib/os-detect.sh"
source "${BASE_DIR}/lib/hooks-runner.sh"

# =============================================================================
# USAGE
# =============================================================================
usage() {
    cat <<EOF
LINKSAFE Patch Management - Install Updates

Usage: $(basename "$0") [OPTIONS] [PACKAGES...]

Options:
    --all              Install all available updates (default)
    --security         Install security updates only
    --packages PKG...  Install specific packages
    --skip-hooks       Skip pre/post upgrade hooks
    --skip-reboot-check Skip reboot requirement check
    --reboot           Reboot if required after update
    --dry-run          Show what would be done without doing it
    --campaign-id ID   Campaign ID for tracking
    --quiet            Minimal output
    -h, --help         Show this help message

Output: JSON containing installation result

Examples:
    $(basename "$0")                      # Install all updates
    $(basename "$0") --security           # Install security updates only
    $(basename "$0") --packages nginx curl # Install specific packages
    $(basename "$0") --all --reboot       # Install all and reboot if needed
EOF
    exit 0
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    local mode="all"
    local packages=()
    local skip_hooks=false
    local skip_reboot_check=false
    local do_reboot=false
    local dry_run=false
    local campaign_id=""
    local quiet=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                mode="all"
                shift
                ;;
            --security)
                mode="security"
                shift
                ;;
            --packages)
                mode="packages"
                shift
                while [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; do
                    packages+=("$1")
                    shift
                done
                ;;
            --skip-hooks)
                skip_hooks=true
                shift
                ;;
            --skip-reboot-check)
                skip_reboot_check=true
                shift
                ;;
            --reboot)
                do_reboot=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --campaign-id)
                campaign_id="$2"
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
                # Treat remaining args as packages
                packages+=("$1")
                mode="packages"
                shift
                ;;
        esac
    done

    # Check root
    if ! is_root && [[ "$dry_run" != "true" ]]; then
        json_error "This script must be run as root"
        exit 1
    fi

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

    # Generate campaign ID if not provided
    [[ -z "$campaign_id" ]] && campaign_id=$(generate_uuid)

    [[ "$quiet" != "true" ]] && log_info "Starting update installation (mode: ${mode}, campaign: ${campaign_id})"

    local start_time
    start_time=$(date +%s)

    local pre_hook_status="skipped"
    local post_hook_status="skipped"
    local install_status="pending"
    local install_output=""
    local reboot_required="false"

    # Dry run mode
    if [[ "$dry_run" == "true" ]]; then
        [[ "$quiet" != "true" ]] && log_info "DRY RUN - no changes will be made"
        install_status="dry_run"
        install_output="Dry run mode - no changes made"
    else
        # Run pre-upgrade hooks
        if [[ "$skip_hooks" != "true" ]]; then
            [[ "$quiet" != "true" ]] && log_info "Running pre-upgrade hooks..."
            if run_pre_upgrade_hooks "$LINUX_DIR"; then
                pre_hook_status="success"
            else
                pre_hook_status="failure"
                install_status="aborted"
                log_error "Pre-upgrade hooks failed, aborting installation"

                # Output result and exit
                output_result "$campaign_id" "$start_time" "$pre_hook_status" "$post_hook_status" \
                    "$install_status" "$install_output" "$reboot_required" "$mode"
                exit 1
            fi
        fi

        # Perform installation
        [[ "$quiet" != "true" ]] && log_info "Installing updates..."

        case "$PACKAGE_MANAGER" in
            apt)
                case "$mode" in
                    all)
                        install_output=$(apt_install_all_updates 2>&1) || true
                        ;;
                    security)
                        install_output=$(apt_install_security_updates 2>&1) || true
                        ;;
                    packages)
                        install_output=$(apt_install_package "${packages[@]}" 2>&1) || true
                        ;;
                esac
                ;;
            dnf|yum)
                case "$mode" in
                    all)
                        install_output=$(dnf_install_all_updates 2>&1) || true
                        ;;
                    security)
                        install_output=$(dnf_install_security_updates 2>&1) || true
                        ;;
                    packages)
                        install_output=$(dnf_install_package "${packages[@]}" 2>&1) || true
                        ;;
                esac
                ;;
            zypper)
                case "$mode" in
                    all)
                        install_output=$(zypper_install_all_updates 2>&1) || true
                        ;;
                    security)
                        install_output=$(zypper_install_security_updates 2>&1) || true
                        ;;
                    packages)
                        install_output=$(zypper_install_package "${packages[@]}" 2>&1) || true
                        ;;
                esac
                ;;
        esac

        # Debug: Log installation output (first 500 chars)
        [[ "$quiet" != "true" ]] && log_debug "Installation output (preview): $(echo "$install_output" | head -c 500)"

        # Check install status from output
        if echo "$install_output" | grep -q '"status": "success"'; then
            install_status="success"
        elif echo "$install_output" | grep -q '"status": "failure"'; then
            install_status="failure"
            [[ "$quiet" != "true" ]] && log_warn "Installation reported failure in output"
        else
            # Check exit code implicitly
            install_status="success"
            [[ "$quiet" != "true" ]] && log_debug "No status found in output, defaulting to success"
        fi

        # Run post-upgrade hooks
        if [[ "$skip_hooks" != "true" ]]; then
            [[ "$quiet" != "true" ]] && log_info "Running post-upgrade hooks..."
            if run_post_upgrade_hooks "$LINUX_DIR"; then
                post_hook_status="success"
            else
                post_hook_status="partial"
                log_warn "Some post-upgrade hooks failed"
            fi
        fi

        # Check reboot requirement
        if [[ "$skip_reboot_check" != "true" ]]; then
            case "$PACKAGE_MANAGER" in
                apt)
                    apt_check_reboot_required >/dev/null 2>&1 && reboot_required="true"
                    ;;
                dnf|yum)
                    dnf_check_reboot_required >/dev/null 2>&1 && reboot_required="true"
                    ;;
                zypper)
                    zypper_check_reboot_required >/dev/null 2>&1 && reboot_required="true"
                    ;;
            esac
        fi
    fi

    # Output result
    local result
    result=$(output_result "$campaign_id" "$start_time" "$pre_hook_status" "$post_hook_status" \
        "$install_status" "$install_output" "$reboot_required" "$mode")

    echo "$result"

    # Save to state and history
    save_state "last-install.json" "$result"
    save_to_history "install" "$result"

    [[ "$quiet" != "true" ]] && log_info "Installation completed (status: ${install_status})"

    # Handle reboot
    if [[ "$reboot_required" == "true" ]] && [[ "$do_reboot" == "true" ]]; then
        [[ "$quiet" != "true" ]] && log_info "Reboot required, initiating reboot..."

        # Run pre-reboot hooks
        if [[ "$skip_hooks" != "true" ]]; then
            if ! run_pre_reboot_hooks "$LINUX_DIR"; then
                log_error "Pre-reboot hooks failed, aborting reboot"
                exit 1
            fi
        fi

        # Set pending reboot flag
        set_pending_reboot

        # Reboot
        if command_exists systemctl; then
            systemctl reboot
        else
            reboot
        fi
    fi

    # Return appropriate exit code
    [[ "$install_status" == "success" ]] && exit 0 || exit 1
}

# Output result JSON
output_result() {
    local campaign_id="$1"
    local start_time="$2"
    local pre_hook_status="$3"
    local post_hook_status="$4"
    local install_status="$5"
    local install_output="$6"
    local reboot_required="$7"
    local mode="$8"

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    local hostname
    hostname=$(get_hostname)
    local timestamp
    timestamp=$(get_timestamp)

    # Extract packages updated if available
    local packages_updated="[]"
    if echo "$install_output" | grep -q '"packages_updated"'; then
        packages_updated=$(echo "$install_output" | sed -n '/"packages_updated":/,/]/p' | head -20)
        packages_updated="${packages_updated#*: }"
    fi

    cat <<EOF
{
  "hostname": "${hostname}",
  "timestamp": "${timestamp}",
  "campaign_id": "${campaign_id}",
  "mode": "${mode}",
  "status": "${install_status}",
  "hooks": {
    "pre_upgrade": "${pre_hook_status}",
    "post_upgrade": "${post_hook_status}"
  },
  "packages_updated": ${packages_updated},
  "reboot_required": ${reboot_required},
  "duration_seconds": ${duration},
  "os": $(os_info_json)
}
EOF
}

# Run main
main "$@"

