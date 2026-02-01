#!/bin/bash
# =============================================================================
# LINKSAFE Post-Upgrade Hook: Send Report
# =============================================================================
# Send upgrade report to logging/monitoring system
# Exit code does not abort (post-upgrade hooks continue on failure)
# =============================================================================

set -euo pipefail

# Configuration
REPORT_ENABLED="${REPORT_ENABLED:-true}"
REPORT_LOG_FILE="${REPORT_LOG_FILE:-/var/log/linksafe-patch.log}"
REPORT_WEBHOOK_URL="${REPORT_WEBHOOK_URL:-}"
REPORT_EMAIL="${REPORT_EMAIL:-}"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [HOOK:send-report] $1"
}

log "Sending upgrade report..."

# If disabled, skip
if [[ "$REPORT_ENABLED" != "true" ]]; then
    log "INFO: Reporting is disabled"
    exit 0
fi

# Gather system info
hostname=$(hostname -f 2>/dev/null || hostname)
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
kernel=$(uname -r)
uptime=$(uptime -p 2>/dev/null || uptime)

# Create report
report=$(cat <<EOF
================================================================================
LINKSAFE Patch Management - Upgrade Report
================================================================================
Hostname:  ${hostname}
Timestamp: ${timestamp}
Kernel:    ${kernel}
Uptime:    ${uptime}
================================================================================
Status: Upgrade completed
================================================================================
EOF
)

# Log to file
if [[ -n "$REPORT_LOG_FILE" ]]; then
    log "Writing report to ${REPORT_LOG_FILE}"
    echo "$report" >> "$REPORT_LOG_FILE" 2>/dev/null || log "WARNING: Could not write to log file"
fi

# Send to webhook
if [[ -n "$REPORT_WEBHOOK_URL" ]]; then
    log "Sending report to webhook..."

    json_report=$(cat <<EOF
{
  "hostname": "${hostname}",
  "timestamp": "${timestamp}",
  "event": "upgrade_completed",
  "kernel": "${kernel}",
  "status": "success"
}
EOF
)

    if command -v curl &>/dev/null; then
        curl -s -X POST "$REPORT_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$json_report" \
            --max-time 10 \
            2>/dev/null || log "WARNING: Failed to send webhook"
    else
        log "WARNING: curl not available for webhook"
    fi
fi

# Send email
if [[ -n "$REPORT_EMAIL" ]]; then
    log "Sending report via email..."

    if command -v mail &>/dev/null; then
        echo "$report" | mail -s "LINKSAFE Patch Report: ${hostname}" "$REPORT_EMAIL" \
            2>/dev/null || log "WARNING: Failed to send email"
    else
        log "WARNING: mail command not available"
    fi
fi

log "PASSED: Report sent"
exit 0
