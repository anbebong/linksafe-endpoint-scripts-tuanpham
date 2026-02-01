#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - OS Detection Library
# =============================================================================
# Detect operating system and map to package manager
# Reference: Rudder package_manager.rs detection logic
# =============================================================================

# Source common library if not already sourced
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
if [[ -z "${LINKSAFE_PATCH_VERSION:-}" ]]; then
    source "${SCRIPT_DIR}/common.sh"
fi

# =============================================================================
# OS DETECTION VARIABLES (set after detection)
# =============================================================================
declare -g OS_ID=""
declare -g OS_NAME=""
declare -g OS_VERSION=""
declare -g OS_VERSION_ID=""
declare -g OS_PRETTY_NAME=""
declare -g OS_FAMILY=""
declare -g PACKAGE_MANAGER=""
declare -g PACKAGE_MANAGER_VERSION=""

# =============================================================================
# OS DETECTION FUNCTIONS
# =============================================================================

# Parse /etc/os-release file
parse_os_release() {
    if [[ -f /etc/os-release ]]; then
        # Source the file to get variables
        # shellcheck disable=SC1091
        source /etc/os-release

        OS_ID="${ID:-unknown}"
        OS_NAME="${NAME:-unknown}"
        OS_VERSION="${VERSION:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-unknown}"
        OS_PRETTY_NAME="${PRETTY_NAME:-unknown}"
        OS_ID_LIKE="${ID_LIKE:-}"

        log_debug "Detected OS: ${OS_PRETTY_NAME} (ID: ${OS_ID})"
        return 0
    fi
    return 1
}

# Fallback OS detection using uname and other methods
fallback_os_detection() {
    local kernel_name
    kernel_name=$(uname -s 2>/dev/null || echo "unknown")

    case "$kernel_name" in
        Linux)
            # Try to detect from various files
            if [[ -f /etc/debian_version ]]; then
                OS_ID="debian"
                OS_NAME="Debian"
                OS_VERSION=$(cat /etc/debian_version)
                OS_FAMILY="debian"
            elif [[ -f /etc/redhat-release ]]; then
                OS_ID="rhel"
                OS_NAME="Red Hat Enterprise Linux"
                OS_VERSION=$(cat /etc/redhat-release | grep -oP '\d+(\.\d+)?')
                OS_FAMILY="rhel"
            elif [[ -f /etc/SuSE-release ]]; then
                OS_ID="sles"
                OS_NAME="SUSE Linux Enterprise Server"
                OS_FAMILY="suse"
            else
                OS_ID="linux"
                OS_NAME="Linux"
                OS_FAMILY="unknown"
            fi
            ;;
        Darwin)
            OS_ID="macos"
            OS_NAME="macOS"
            OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
            OS_FAMILY="darwin"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            OS_ID="windows"
            OS_NAME="Windows"
            OS_FAMILY="windows"
            ;;
        *)
            OS_ID="unknown"
            OS_NAME="Unknown"
            OS_FAMILY="unknown"
            ;;
    esac

    OS_PRETTY_NAME="${OS_NAME} ${OS_VERSION}"
    OS_VERSION_ID="${OS_VERSION}"
}

# Determine OS family from OS ID
determine_os_family() {
    case "$OS_ID" in
        debian|ubuntu|linuxmint|pop|elementary|zorin|kali|parrot|raspbian)
            OS_FAMILY="debian"
            ;;
        fedora|centos|rhel|rocky|almalinux|oracle|amzn|amazon|scientific|eurolinux)
            OS_FAMILY="rhel"
            ;;
        sles|sled|opensuse|opensuse-leap|opensuse-tumbleweed)
            OS_FAMILY="suse"
            ;;
        arch|manjaro|endeavouros)
            OS_FAMILY="arch"
            ;;
        alpine)
            OS_FAMILY="alpine"
            ;;
        *)
            # Try to determine from ID_LIKE if available
            if [[ -n "${OS_ID_LIKE:-}" ]]; then
                if [[ "$OS_ID_LIKE" == *"debian"* ]] || [[ "$OS_ID_LIKE" == *"ubuntu"* ]]; then
                    OS_FAMILY="debian"
                elif [[ "$OS_ID_LIKE" == *"rhel"* ]] || [[ "$OS_ID_LIKE" == *"fedora"* ]] || [[ "$OS_ID_LIKE" == *"centos"* ]]; then
                    OS_FAMILY="rhel"
                elif [[ "$OS_ID_LIKE" == *"suse"* ]]; then
                    OS_FAMILY="suse"
                else
                    OS_FAMILY="unknown"
                fi
            else
                OS_FAMILY="unknown"
            fi
            ;;
    esac

    log_debug "OS Family: ${OS_FAMILY}"
}

# =============================================================================
# PACKAGE MANAGER DETECTION
# =============================================================================

# Detect package manager based on OS family
detect_package_manager() {
    case "$OS_FAMILY" in
        debian)
            if command_exists apt-get; then
                PACKAGE_MANAGER="apt"
                PACKAGE_MANAGER_VERSION=$(apt-get --version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")
            else
                log_error "APT not found on Debian-based system"
                return 1
            fi
            ;;
        rhel)
            if command_exists dnf; then
                PACKAGE_MANAGER="dnf"
                PACKAGE_MANAGER_VERSION=$(dnf --version 2>/dev/null | head -1 || echo "unknown")
            elif command_exists yum; then
                PACKAGE_MANAGER="yum"
                PACKAGE_MANAGER_VERSION=$(yum --version 2>/dev/null | head -1 || echo "unknown")
            else
                log_error "DNF/YUM not found on RHEL-based system"
                return 1
            fi
            ;;
        suse)
            if command_exists zypper; then
                PACKAGE_MANAGER="zypper"
                PACKAGE_MANAGER_VERSION=$(zypper --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            else
                log_error "Zypper not found on SUSE-based system"
                return 1
            fi
            ;;
        arch)
            if command_exists pacman; then
                PACKAGE_MANAGER="pacman"
                PACKAGE_MANAGER_VERSION=$(pacman --version 2>/dev/null | head -1 | awk '{print $3}' || echo "unknown")
            else
                log_error "Pacman not found on Arch-based system"
                return 1
            fi
            ;;
        alpine)
            if command_exists apk; then
                PACKAGE_MANAGER="apk"
                PACKAGE_MANAGER_VERSION=$(apk --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            else
                log_error "APK not found on Alpine system"
                return 1
            fi
            ;;
        darwin)
            if command_exists brew; then
                PACKAGE_MANAGER="brew"
                PACKAGE_MANAGER_VERSION=$(brew --version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")
            else
                PACKAGE_MANAGER="none"
                log_warn "No package manager detected on macOS (Homebrew not installed)"
            fi
            ;;
        *)
            # Try to detect any available package manager
            if command_exists apt-get; then
                PACKAGE_MANAGER="apt"
                OS_FAMILY="debian"
            elif command_exists dnf; then
                PACKAGE_MANAGER="dnf"
                OS_FAMILY="rhel"
            elif command_exists yum; then
                PACKAGE_MANAGER="yum"
                OS_FAMILY="rhel"
            elif command_exists zypper; then
                PACKAGE_MANAGER="zypper"
                OS_FAMILY="suse"
            elif command_exists pacman; then
                PACKAGE_MANAGER="pacman"
                OS_FAMILY="arch"
            elif command_exists apk; then
                PACKAGE_MANAGER="apk"
                OS_FAMILY="alpine"
            else
                PACKAGE_MANAGER="unknown"
                log_error "No supported package manager found"
                return 1
            fi
            ;;
    esac

    log_debug "Package Manager: ${PACKAGE_MANAGER} (${PACKAGE_MANAGER_VERSION})"
    return 0
}

# =============================================================================
# MAIN DETECTION FUNCTION
# =============================================================================

# Run full OS detection
detect_os() {
    log_debug "Starting OS detection..."

    # Try /etc/os-release first
    if ! parse_os_release; then
        log_debug "os-release not found, using fallback detection"
        fallback_os_detection
    fi

    # Determine OS family
    determine_os_family

    # Detect package manager
    if ! detect_package_manager; then
        log_error "Failed to detect package manager"
        return 1
    fi

    log_info "Detected: ${OS_PRETTY_NAME} with ${PACKAGE_MANAGER}"
    return 0
}

# =============================================================================
# JSON OUTPUT
# =============================================================================

# Output OS info as JSON
os_info_json() {
    cat <<EOF
{
  "id": $(json_string "$OS_ID"),
  "name": $(json_string "$OS_NAME"),
  "version": $(json_string "$OS_VERSION"),
  "version_id": $(json_string "$OS_VERSION_ID"),
  "pretty_name": $(json_string "$OS_PRETTY_NAME"),
  "family": $(json_string "$OS_FAMILY"),
  "package_manager": $(json_string "$PACKAGE_MANAGER"),
  "package_manager_version": $(json_string "$PACKAGE_MANAGER_VERSION")
}
EOF
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Check if OS is supported
is_os_supported() {
    case "$PACKAGE_MANAGER" in
        apt|dnf|yum|zypper)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get package manager library path
get_package_manager_lib() {
    # First try same directory as this script (installed location)
    local script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    local base_dir="${1:-$script_dir}"

    case "$PACKAGE_MANAGER" in
        apt)
            echo "${base_dir}/apt.sh"
            ;;
        dnf|yum)
            echo "${base_dir}/dnf.sh"
            ;;
        zypper)
            echo "${base_dir}/zypper.sh"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Source the appropriate package manager library
source_package_manager_lib() {
    local lib_path
    lib_path=$(get_package_manager_lib)

    if [[ -n "$lib_path" ]] && [[ -f "$lib_path" ]]; then
        # shellcheck disable=SC1090
        source "$lib_path"
        return 0
    else
        log_error "Package manager library not found: ${lib_path}"
        return 1
    fi
}

# =============================================================================
# AUTO-DETECT ON SOURCE
# =============================================================================

# Run detection when sourced
detect_os
