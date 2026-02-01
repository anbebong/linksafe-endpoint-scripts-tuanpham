#!/bin/bash
#
# LINKSAFE Patch Management - Installer
#
# Usage: ./install.sh [options]
#   --prefix PATH    Installation prefix (default: /opt/linksafe-patch)
#   --no-hooks       Don't install hook examples
#   --help           Show this help
#

set -e

# Defaults
PREFIX="/opt/linksafe-patch"
INSTALL_HOOKS=true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
LINKSAFE Patch Management - Installer

Usage: ./install.sh [options]

Options:
    --prefix PATH    Installation prefix (default: /opt/linksafe-patch)
    --no-hooks       Don't install hook examples
    --help           Show this help

Examples:
    ./install.sh
    ./install.sh --prefix /usr/local/linksafe-patch
    ./install.sh --no-hooks
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --no-hooks)
            INSTALL_HOOKS=false
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
log_info "Detected OS: $OS"

# Create directories
log_info "Creating directories at $PREFIX"
mkdir -p "$PREFIX"/{lib,actions,hooks.d/{pre-upgrade,pre-reboot,post-upgrade},state,logs}

# Install common libraries
log_info "Installing common libraries..."
cp "$SCRIPT_DIR/lib/common.sh" "$PREFIX/lib/"
cp "$SCRIPT_DIR/lib/os-detect.sh" "$PREFIX/lib/"
cp "$SCRIPT_DIR/lib/hooks-runner.sh" "$PREFIX/lib/"
chmod 644 "$PREFIX/lib/"*.sh

# Install Linux-specific files
if [[ -d "$SCRIPT_DIR/linux" ]]; then
    log_info "Installing Linux package manager libraries..."

    # Package manager libraries
    cp "$SCRIPT_DIR/linux/lib/apt.sh" "$PREFIX/lib/" 2>/dev/null || true
    cp "$SCRIPT_DIR/linux/lib/dnf.sh" "$PREFIX/lib/" 2>/dev/null || true
    cp "$SCRIPT_DIR/linux/lib/zypper.sh" "$PREFIX/lib/" 2>/dev/null || true
    chmod 644 "$PREFIX/lib/"*.sh 2>/dev/null || true

    # Actions
    log_info "Installing action scripts..."
    cp "$SCRIPT_DIR/linux/actions/"*.sh "$PREFIX/actions/"
    chmod 755 "$PREFIX/actions/"*.sh

    # Hooks
    if $INSTALL_HOOKS; then
        log_info "Installing hook examples..."

        # Copy and keep disabled hooks as disabled
        for hook_type in pre-upgrade pre-reboot post-upgrade; do
            if [[ -d "$SCRIPT_DIR/linux/hooks.d/$hook_type" ]]; then
                cp "$SCRIPT_DIR/linux/hooks.d/$hook_type/"* "$PREFIX/hooks.d/$hook_type/" 2>/dev/null || true
            fi
        done

        # Set permissions on hooks
        find "$PREFIX/hooks.d" -name "*.sh" -exec chmod 755 {} \;
        find "$PREFIX/hooks.d" -name "*.sh.disabled" -exec chmod 644 {} \;
    fi
fi

# Create symlinks for easy access
log_info "Creating symlinks..."
ln -sf "$PREFIX/actions/check-updates.sh" /usr/local/bin/linksafe-check-updates 2>/dev/null || true
ln -sf "$PREFIX/actions/install-updates.sh" /usr/local/bin/linksafe-install-updates 2>/dev/null || true
ln -sf "$PREFIX/actions/check-reboot.sh" /usr/local/bin/linksafe-check-reboot 2>/dev/null || true
ln -sf "$PREFIX/actions/list-installed.sh" /usr/local/bin/linksafe-list-installed 2>/dev/null || true

# Set ownership
chown -R root:root "$PREFIX"

# Create state directory with proper permissions
chmod 755 "$PREFIX/state"
chmod 755 "$PREFIX/logs"

# Summary
log_info "Installation complete!"
echo ""
echo "Installation Summary:"
echo "  Location: $PREFIX"
echo "  Actions:  $PREFIX/actions/"
echo "  Hooks:    $PREFIX/hooks.d/"
echo "  State:    $PREFIX/state/"
echo "  Logs:     $PREFIX/logs/"
echo ""
echo "Commands available:"
echo "  linksafe-check-updates    - Check for available updates"
echo "  linksafe-install-updates  - Install updates"
echo "  linksafe-check-reboot     - Check if reboot required"
echo "  linksafe-list-installed   - List installed packages"
echo ""
echo "To enable a disabled hook:"
echo "  mv $PREFIX/hooks.d/pre-upgrade/XX-example.sh.disabled \\"
echo "     $PREFIX/hooks.d/pre-upgrade/XX-example.sh"
echo ""
echo "To run tests:"
echo "  $SCRIPT_DIR/tests/test-linux.sh"
