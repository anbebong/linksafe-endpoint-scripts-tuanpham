#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - Install Security Updates
# =============================================================================
# Convenience wrapper for installing security updates only
# Usage: install-security.sh [OPTIONS]
# =============================================================================

set -euo pipefail

# Get script directory (resolve symlinks)
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Simply call install-updates.sh with --security flag
exec "${SCRIPT_DIR}/install-updates.sh" --security "$@"
