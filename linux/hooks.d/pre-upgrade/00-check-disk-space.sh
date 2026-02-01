#!/bin/bash
# =============================================================================
# LINKSAFE Pre-Upgrade Hook: Check Disk Space
# =============================================================================
# Verify sufficient disk space before upgrade
# Exit 0 = continue, Exit non-zero = abort upgrade
# =============================================================================

set -euo pipefail

# Configuration
REQUIRED_SPACE_MB="${REQUIRED_SPACE_MB:-1024}"  # 1GB default
CHECK_PATHS="${CHECK_PATHS:-/ /var /tmp}"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [HOOK:disk-space] $1"
}

log "Checking disk space (required: ${REQUIRED_SPACE_MB}MB)..."

failed=false

for path in $CHECK_PATHS; do
    if [[ ! -d "$path" ]]; then
        continue
    fi

    # Get available space in MB
    available_mb=$(df -BM "$path" 2>/dev/null | awk 'NR==2 {gsub(/M/,"",$4); print $4}')

    if [[ -z "$available_mb" ]]; then
        log "WARNING: Could not determine space for $path"
        continue
    fi

    if [[ "$available_mb" -lt "$REQUIRED_SPACE_MB" ]]; then
        log "ERROR: Insufficient space on $path: ${available_mb}MB available, ${REQUIRED_SPACE_MB}MB required"
        failed=true
    else
        log "OK: $path has ${available_mb}MB available"
    fi
done

if [[ "$failed" == "true" ]]; then
    log "FAILED: Insufficient disk space - aborting upgrade"
    exit 1
fi

log "PASSED: Sufficient disk space available"
exit 0
