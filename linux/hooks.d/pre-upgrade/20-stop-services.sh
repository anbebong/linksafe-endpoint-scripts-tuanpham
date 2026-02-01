#!/bin/bash
# =============================================================================
# LINKSAFE Pre-Upgrade Hook: Stop Services
# =============================================================================
# Stop services before upgrade (customize for your environment)
# Exit 0 = continue, Exit non-zero = abort upgrade
# =============================================================================

set -euo pipefail

# Configuration - customize these services for your environment
SERVICES_TO_STOP="${SERVICES_TO_STOP:-}"
STOP_SERVICES_ENABLED="${STOP_SERVICES_ENABLED:-false}"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [HOOK:stop-services] $1"
}

log "Checking services to stop before upgrade..."

# If disabled, skip
if [[ "$STOP_SERVICES_ENABLED" != "true" ]]; then
    log "INFO: Service stopping is disabled (STOP_SERVICES_ENABLED=false)"
    exit 0
fi

# If no services configured
if [[ -z "$SERVICES_TO_STOP" ]]; then
    log "INFO: No services configured to stop (SERVICES_TO_STOP is empty)"
    exit 0
fi

# Stop each service
for service in $SERVICES_TO_STOP; do
    log "Stopping service: $service"

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        if systemctl stop "$service" 2>/dev/null; then
            log "OK: Stopped $service"
        else
            log "ERROR: Failed to stop $service"
            exit 1
        fi
    else
        log "INFO: Service $service is not running"
    fi
done

log "PASSED: All configured services stopped"
exit 0
