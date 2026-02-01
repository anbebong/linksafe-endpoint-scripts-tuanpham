#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - Common Library
# =============================================================================
# Shared functions for logging, JSON output, error handling
# Reference: Rudder system-updates module patterns
# =============================================================================

set -euo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly LINKSAFE_PATCH_VERSION="1.0.0"
readonly LINKSAFE_STATE_DIR="/var/lib/linksafe-patch"
readonly LINKSAFE_LOG_FILE="/var/log/linksafe-patch.log"
readonly LINKSAFE_HISTORY_DIR="${LINKSAFE_STATE_DIR}/history"

# Colors for terminal output (disabled if not tty)
if [[ -t 1 ]]; then
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_NC='\033[0m'
else
    readonly COLOR_RED=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
    readonly COLOR_BLUE=''
    readonly COLOR_NC=''
fi

# =============================================================================
# LOGGING FUNCTIONS (Prefix-based format for easy parsing)
# Format: LOG:timestamp:level:message
# Format: DATA:json
# =============================================================================

# Get ISO8601 timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get date for filenames
get_date_string() {
    date +"%Y-%m-%d"
}

# Internal log function - outputs LOG:timestamp:level:message format
_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(get_timestamp)

    # Output in prefix format for parsing: LOG:timestamp:level:message
    echo "LOG:${timestamp}:${level}:${message}"

    # Also log to file if writable
    if [[ -w "${LINKSAFE_LOG_FILE}" ]] || [[ -w "$(dirname "${LINKSAFE_LOG_FILE}")" ]]; then
        echo "LOG:${timestamp}:${level}:${message}" >> "${LINKSAFE_LOG_FILE}" 2>/dev/null || true
    fi
}

log_info() {
    _log "INFO" "$1"
}

log_warn() {
    _log "WARN" "$1"
}

log_error() {
    _log "ERROR" "$1"
}

log_debug() {
    if [[ "${LINKSAFE_DEBUG:-0}" == "1" ]]; then
        _log "DEBUG" "$1"
    fi
}

# Output data with DATA: prefix - for JSON payloads
output_data() {
    local json="$1"
    echo "DATA:${json}"
}

# =============================================================================
# JSON OUTPUT FUNCTIONS
# =============================================================================

# Escape string for JSON
json_escape() {
    local string="$1"
    # Escape backslashes, quotes, and control characters
    string="${string//\\/\\\\}"
    string="${string//\"/\\\"}"
    string="${string//$'\n'/\\n}"
    string="${string//$'\r'/\\r}"
    string="${string//$'\t'/\\t}"
    echo -n "$string"
}

# Output JSON string value
json_string() {
    local value="$1"
    echo -n "\"$(json_escape "$value")\""
}

# Output JSON boolean
json_bool() {
    local value="$1"
    if [[ "$value" == "true" ]] || [[ "$value" == "1" ]] || [[ "$value" == "yes" ]]; then
        echo -n "true"
    else
        echo -n "false"
    fi
}

# Output JSON number
json_number() {
    local value="$1"
    echo -n "${value:-0}"
}

# Start JSON object output
json_start_object() {
    echo "{"
}

# End JSON object output
json_end_object() {
    echo "}"
}

# Start JSON array output
json_start_array() {
    echo "["
}

# End JSON array output
json_end_array() {
    echo "]"
}

# Output a simple JSON error response with DATA: prefix
json_error() {
    local message="$1"
    local code="${2:-1}"
    local json
    json=$(cat <<EOF
{"status":"error","error":{"code":${code},"message":$(json_string "$message")},"timestamp":"$(get_timestamp)","hostname":"$(get_hostname)"}
EOF
)
    output_data "$json"
}

# Output a simple JSON success response with DATA: prefix
json_success() {
    local message="${1:-Operation completed successfully}"
    local json
    json=$(cat <<EOF
{"status":"success","message":$(json_string "$message"),"timestamp":"$(get_timestamp)","hostname":"$(get_hostname)"}
EOF
)
    output_data "$json"
}

# =============================================================================
# SYSTEM FUNCTIONS
# =============================================================================

# Get hostname
get_hostname() {
    hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        json_error "This script must be run as root" 1
        exit 1
    fi
}

# Check if running as root (non-fatal, returns status)
is_root() {
    [[ $EUID -eq 0 ]]
}

# Run command with timeout
run_with_timeout() {
    local timeout_seconds="$1"
    shift
    local command=("$@")

    if command -v timeout &>/dev/null; then
        timeout "${timeout_seconds}s" "${command[@]}"
    else
        # Fallback without timeout
        "${command[@]}"
    fi
}

# Get available disk space in bytes
get_available_disk_space() {
    local path="${1:-/}"
    df -B1 "$path" 2>/dev/null | awk 'NR==2 {print $4}'
}

# Get available disk space in human readable format
get_available_disk_space_human() {
    local path="${1:-/}"
    df -h "$path" 2>/dev/null | awk 'NR==2 {print $4}'
}

# Check if minimum disk space is available (in MB)
check_disk_space() {
    local required_mb="${1:-1024}"  # Default 1GB
    local path="${2:-/}"
    local available_bytes
    available_bytes=$(get_available_disk_space "$path")
    local required_bytes=$((required_mb * 1024 * 1024))

    if [[ -z "$available_bytes" ]]; then
        log_warn "Could not determine available disk space"
        return 1
    fi

    if [[ "$available_bytes" -lt "$required_bytes" ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# STATE MANAGEMENT FUNCTIONS
# =============================================================================

# Ensure state directory exists
ensure_state_dir() {
    if [[ ! -d "${LINKSAFE_STATE_DIR}" ]]; then
        mkdir -p "${LINKSAFE_STATE_DIR}" 2>/dev/null || true
        mkdir -p "${LINKSAFE_HISTORY_DIR}" 2>/dev/null || true
        chmod 750 "${LINKSAFE_STATE_DIR}" 2>/dev/null || true
    fi
}

# Save state to file
save_state() {
    local filename="$1"
    local content="$2"
    ensure_state_dir
    echo "$content" > "${LINKSAFE_STATE_DIR}/${filename}"
}

# Load state from file
load_state() {
    local filename="$1"
    local filepath="${LINKSAFE_STATE_DIR}/${filename}"
    if [[ -f "$filepath" ]]; then
        cat "$filepath"
    else
        echo ""
    fi
}

# Save to history
save_to_history() {
    local action="$1"
    local content="$2"
    ensure_state_dir
    local date_str
    date_str=$(get_date_string)
    local timestamp
    timestamp=$(date +%H%M%S)
    echo "$content" > "${LINKSAFE_HISTORY_DIR}/${date_str}-${action}-${timestamp}.json"
}

# Set pending reboot flag
set_pending_reboot() {
    ensure_state_dir
    touch "${LINKSAFE_STATE_DIR}/pending-reboot"
}

# Clear pending reboot flag
clear_pending_reboot() {
    rm -f "${LINKSAFE_STATE_DIR}/pending-reboot" 2>/dev/null || true
}

# Check if reboot is pending (from our tracking)
is_reboot_pending() {
    [[ -f "${LINKSAFE_STATE_DIR}/pending-reboot" ]]
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Get script directory
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -h "$source" ]]; do
        local dir
        dir=$(cd -P "$(dirname "$source")" && pwd)
        source=$(readlink "$source")
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

# Trim whitespace
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

# Compare versions (returns 0 if v1 >= v2)
version_gte() {
    local v1="$1"
    local v2="$2"
    [[ "$(printf '%s\n' "$v2" "$v1" | sort -V | head -n1)" == "$v2" ]]
}

# Generate UUID (simple version)
generate_uuid() {
    if command_exists uuidgen; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback: generate pseudo-random UUID
        printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x\n' \
            $RANDOM $RANDOM $RANDOM \
            $(($RANDOM & 0x0fff | 0x4000)) \
            $(($RANDOM & 0x3fff | 0x8000)) \
            $RANDOM $RANDOM $RANDOM
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize common library
init_common() {
    # Ensure log file directory exists
    local log_dir
    log_dir=$(dirname "${LINKSAFE_LOG_FILE}")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi

    # Ensure state directory exists
    ensure_state_dir

    log_debug "LINKSAFE Patch Management v${LINKSAFE_PATCH_VERSION} initialized"
}

# Auto-initialize when sourced
init_common
