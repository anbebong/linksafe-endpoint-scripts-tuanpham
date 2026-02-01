#!/bin/bash
# =============================================================================
# LINKSAFE Pre-Upgrade Hook: Backup Check
# =============================================================================
# Verify recent backup exists (customize for your backup solution)
# Exit 0 = continue, Exit non-zero = abort upgrade
# =============================================================================

set -euo pipefail

# Configuration - customize these for your environment
BACKUP_CHECK_ENABLED="${BACKUP_CHECK_ENABLED:-false}"
BACKUP_MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS:-24}"
BACKUP_STATUS_FILE="${BACKUP_STATUS_FILE:-/var/lib/backup/last-backup}"
BACKUP_CHECK_COMMAND="${BACKUP_CHECK_COMMAND:-}"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [HOOK:backup-check] $1"
}

log "Checking backup status..."

# If backup check is disabled, just log warning and continue
if [[ "$BACKUP_CHECK_ENABLED" != "true" ]]; then
    log "WARNING: Backup check is disabled (BACKUP_CHECK_ENABLED=false)"
    log "WARNING: Proceeding without backup verification"
    exit 0
fi

# Method 1: Check backup status file
if [[ -n "$BACKUP_STATUS_FILE" ]] && [[ -f "$BACKUP_STATUS_FILE" ]]; then
    # Get file modification time
    file_age_seconds=$(($(date +%s) - $(stat -c %Y "$BACKUP_STATUS_FILE" 2>/dev/null || echo 0)))
    max_age_seconds=$((BACKUP_MAX_AGE_HOURS * 3600))

    if [[ "$file_age_seconds" -gt "$max_age_seconds" ]]; then
        log "ERROR: Backup status file is older than ${BACKUP_MAX_AGE_HOURS} hours"
        log "ERROR: Last backup: $(stat -c %y "$BACKUP_STATUS_FILE" 2>/dev/null || echo 'unknown')"
        exit 1
    fi

    log "OK: Recent backup found (age: $((file_age_seconds / 3600)) hours)"
    exit 0
fi

# Method 2: Run custom backup check command
if [[ -n "$BACKUP_CHECK_COMMAND" ]]; then
    log "Running custom backup check command..."
    if eval "$BACKUP_CHECK_COMMAND"; then
        log "OK: Custom backup check passed"
        exit 0
    else
        log "ERROR: Custom backup check failed"
        exit 1
    fi
fi

# No backup verification configured
log "WARNING: No backup verification configured"
log "WARNING: Set BACKUP_CHECK_ENABLED=true and configure backup check"
exit 0
