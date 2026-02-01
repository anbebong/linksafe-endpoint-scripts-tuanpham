#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - Hooks Runner Library
# =============================================================================
# Execute pre/post upgrade hooks following Rudder patterns
# Reference: Rudder hooks.rs implementation
# =============================================================================

# Source common library if not already sourced
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
if [[ -z "${LINKSAFE_PATCH_VERSION:-}" ]]; then
    source "${SCRIPT_DIR}/common.sh"
fi

# =============================================================================
# CONSTANTS
# =============================================================================
readonly HOOKS_DIR_NAME="hooks.d"
readonly HOOK_TYPE_PRE_UPGRADE="pre-upgrade"
readonly HOOK_TYPE_PRE_REBOOT="pre-reboot"
readonly HOOK_TYPE_POST_UPGRADE="post-upgrade"

# =============================================================================
# HOOK VALIDATION (from Rudder hooks.rs)
# =============================================================================

# Check if a hook file is runnable
# Following Rudder's security checks:
# - File has executable permissions
# - File is not world-writable
# - File is owned by root (or current user if not root)
hook_is_runnable() {
    local hook_file="$1"

    # Check if file exists
    if [[ ! -f "$hook_file" ]]; then
        log_debug "Hook file does not exist: ${hook_file}"
        return 1
    fi

    # Check if file is executable
    if [[ ! -x "$hook_file" ]]; then
        log_debug "Hook file is not executable: ${hook_file}"
        return 1
    fi

    # Get file permissions
    local file_mode
    file_mode=$(stat -c %a "$hook_file" 2>/dev/null || stat -f %Lp "$hook_file" 2>/dev/null)

    # Check if world-writable (last digit has write bit = 2, 3, 6, 7)
    local world_perms=$((file_mode % 10))
    if [[ $((world_perms & 2)) -ne 0 ]]; then
        log_warn "Hook file is world-writable (security risk), skipping: ${hook_file}"
        return 1
    fi

    # Check ownership if running as root
    if is_root; then
        local file_owner
        file_owner=$(stat -c %u "$hook_file" 2>/dev/null || stat -f %u "$hook_file" 2>/dev/null)
        if [[ "$file_owner" != "0" ]]; then
            log_warn "Hook file is not owned by root, skipping: ${hook_file}"
            return 1
        fi
    fi

    return 0
}

# =============================================================================
# HOOK EXECUTION
# =============================================================================

# Execute a single hook
execute_hook() {
    local hook_file="$1"
    local hook_name
    hook_name=$(basename "$hook_file")

    log_info "Executing hook: ${hook_name}"

    local start_time
    start_time=$(date +%s)

    local output
    local exit_code

    # Execute hook and capture output
    # shellcheck disable=SC2086
    if output=$("$hook_file" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ $exit_code -eq 0 ]]; then
        log_info "Hook ${hook_name} completed successfully (${duration}s)"
        log_debug "Hook output: ${output}"
        return 0
    else
        log_error "Hook ${hook_name} failed with exit code ${exit_code} (${duration}s)"
        log_error "Hook output: ${output}"
        return $exit_code
    fi
}

# Run all hooks in a directory
# Parameters:
#   $1 - hooks directory path
#   $2 - fail_fast (true/false) - stop on first failure
# Returns:
#   0 - all hooks succeeded
#   1 - at least one hook failed
run_hooks_dir() {
    local hooks_dir="$1"
    local fail_fast="${2:-true}"

    local hook_type
    hook_type=$(basename "$hooks_dir")

    log_info "Running ${hook_type} hooks from: ${hooks_dir}"

    # Check if directory exists
    if [[ ! -d "$hooks_dir" ]]; then
        log_debug "Hooks directory does not exist: ${hooks_dir}"
        return 0
    fi

    # Get list of hook files, sorted alphabetically
    local hooks=()
    while IFS= read -r -d '' hook_file; do
        hooks+=("$hook_file")
    done < <(find "$hooks_dir" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)

    if [[ ${#hooks[@]} -eq 0 ]]; then
        log_debug "No hooks found in: ${hooks_dir}"
        return 0
    fi

    log_info "Found ${#hooks[@]} hook(s) to execute"

    local failed_count=0
    local success_count=0
    local skipped_count=0

    for hook_file in "${hooks[@]}"; do
        local hook_name
        hook_name=$(basename "$hook_file")

        # Validate hook is runnable
        if ! hook_is_runnable "$hook_file"; then
            log_debug "Skipping non-runnable hook: ${hook_name}"
            ((skipped_count++))
            continue
        fi

        # Execute hook
        if execute_hook "$hook_file"; then
            ((success_count++))
        else
            ((failed_count++))

            # Stop on first failure if fail_fast is enabled
            if [[ "$fail_fast" == "true" ]]; then
                log_error "Stopping hook execution due to failure (fail_fast=true)"
                break
            fi
        fi
    done

    log_info "Hooks summary: ${success_count} succeeded, ${failed_count} failed, ${skipped_count} skipped"

    if [[ $failed_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# HOOK TYPE RUNNERS
# =============================================================================

# Get hooks directory for a specific type
get_hooks_dir() {
    local base_dir="$1"
    local hook_type="$2"
    echo "${base_dir}/${HOOKS_DIR_NAME}/${hook_type}"
}

# Run pre-upgrade hooks
# Pre-upgrade hooks use fail_fast=true (stop on first failure)
run_pre_upgrade_hooks() {
    local base_dir="${1:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")/linux}"
    local hooks_dir
    hooks_dir=$(get_hooks_dir "$base_dir" "$HOOK_TYPE_PRE_UPGRADE")

    log_info "=== Running Pre-Upgrade Hooks ==="
    if run_hooks_dir "$hooks_dir" "true"; then
        log_info "Pre-upgrade hooks completed successfully"
        return 0
    else
        log_error "Pre-upgrade hooks failed - aborting upgrade"
        return 1
    fi
}

# Run pre-reboot hooks
# Pre-reboot hooks use fail_fast=true (stop on first failure)
run_pre_reboot_hooks() {
    local base_dir="${1:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")/linux}"
    local hooks_dir
    hooks_dir=$(get_hooks_dir "$base_dir" "$HOOK_TYPE_PRE_REBOOT")

    log_info "=== Running Pre-Reboot Hooks ==="
    if run_hooks_dir "$hooks_dir" "true"; then
        log_info "Pre-reboot hooks completed successfully"
        return 0
    else
        log_error "Pre-reboot hooks failed - aborting reboot"
        return 1
    fi
}

# Run post-upgrade hooks
# Post-upgrade hooks use fail_fast=false (continue on failure)
run_post_upgrade_hooks() {
    local base_dir="${1:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")/linux}"
    local hooks_dir
    hooks_dir=$(get_hooks_dir "$base_dir" "$HOOK_TYPE_POST_UPGRADE")

    log_info "=== Running Post-Upgrade Hooks ==="
    if run_hooks_dir "$hooks_dir" "false"; then
        log_info "Post-upgrade hooks completed successfully"
        return 0
    else
        log_warn "Some post-upgrade hooks failed (continuing anyway)"
        return 0  # Don't fail the overall process for post-upgrade hook failures
    fi
}

# =============================================================================
# JSON OUTPUT
# =============================================================================

# Output hooks execution result as JSON
hooks_result_json() {
    local hook_type="$1"
    local status="$2"  # success/failure
    local message="${3:-}"

    cat <<EOF
{
  "hook_type": $(json_string "$hook_type"),
  "status": $(json_string "$status"),
  "message": $(json_string "$message"),
  "timestamp": "$(get_timestamp)"
}
EOF
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# List all hooks for a given type
list_hooks() {
    local base_dir="${1:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")/linux}"
    local hook_type="${2:-all}"

    local types=()
    if [[ "$hook_type" == "all" ]]; then
        types=("$HOOK_TYPE_PRE_UPGRADE" "$HOOK_TYPE_PRE_REBOOT" "$HOOK_TYPE_POST_UPGRADE")
    else
        types=("$hook_type")
    fi

    echo "{"
    echo "  \"hooks\": {"

    local first_type=true
    for type in "${types[@]}"; do
        local hooks_dir
        hooks_dir=$(get_hooks_dir "$base_dir" "$type")

        [[ "$first_type" != "true" ]] && echo ","
        first_type=false

        echo "    \"${type}\": ["

        if [[ -d "$hooks_dir" ]]; then
            local first_hook=true
            while IFS= read -r -d '' hook_file; do
                [[ "$first_hook" != "true" ]] && echo ","
                first_hook=false

                local hook_name
                hook_name=$(basename "$hook_file")
                local is_runnable="false"
                hook_is_runnable "$hook_file" && is_runnable="true"

                echo -n "      {\"name\": \"${hook_name}\", \"runnable\": ${is_runnable}}"
            done < <(find "$hooks_dir" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
        fi

        echo ""
        echo -n "    ]"
    done

    echo ""
    echo "  }"
    echo "}"
}

# Create a new hook from template
create_hook() {
    local base_dir="$1"
    local hook_type="$2"
    local hook_name="$3"
    local content="${4:-}"

    local hooks_dir
    hooks_dir=$(get_hooks_dir "$base_dir" "$hook_type")

    # Create hooks directory if not exists
    mkdir -p "$hooks_dir"

    local hook_file="${hooks_dir}/${hook_name}"

    if [[ -f "$hook_file" ]]; then
        log_error "Hook already exists: ${hook_file}"
        return 1
    fi

    # Create hook with default template if no content provided
    if [[ -z "$content" ]]; then
        content=$(cat <<'TEMPLATE'
#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management Hook
# =============================================================================
# Hook Type: ${HOOK_TYPE}
# Hook Name: ${HOOK_NAME}
# =============================================================================

set -euo pipefail

# Add your hook logic here
echo "Running hook: $(basename "$0")"

# Exit 0 for success, non-zero for failure
exit 0
TEMPLATE
)
        content="${content//\$\{HOOK_TYPE\}/$hook_type}"
        content="${content//\$\{HOOK_NAME\}/$hook_name}"
    fi

    echo "$content" > "$hook_file"
    chmod 750 "$hook_file"

    if is_root; then
        chown root:root "$hook_file"
    fi

    log_info "Created hook: ${hook_file}"
    return 0
}

# Enable/disable a hook (by changing permissions)
enable_hook() {
    local hook_file="$1"
    chmod +x "$hook_file"
    log_info "Enabled hook: ${hook_file}"
}

disable_hook() {
    local hook_file="$1"
    chmod -x "$hook_file"
    log_info "Disabled hook: ${hook_file}"
}
