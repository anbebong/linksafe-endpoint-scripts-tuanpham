#!/bin/bash
# =============================================================================
# LINKSAFE Post-Upgrade Hook: Verify Services
# =============================================================================
# Verify critical services are running after upgrade
# Exit code does not abort (post-upgrade hooks continue on failure)
# =============================================================================

set -euo pipefail

# Configuration - customize these services for your environment
CRITICAL_SERVICES="${CRITICAL_SERVICES:-sshd cron}"
VERIFY_SERVICES_ENABLED="${VERIFY_SERVICES_ENABLED:-true}"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [HOOK:verify-services] $1"
}

log "Verifying critical services after upgrade..."

# If disabled, skip
if [[ "$VERIFY_SERVICES_ENABLED" != "true" ]]; then
    log "INFO: Service verification is disabled"
    exit 0
fi

# If no services configured
if [[ -z "$CRITICAL_SERVICES" ]]; then
    log "INFO: No critical services configured to verify"
    exit 0
fi

failed_services=()

# Check each service
for service in $CRITICAL_SERVICES; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log "OK: Service $service is running"
    else
        log "WARNING: Service $service is NOT running"

        # Try to start it
        log "Attempting to start $service..."
        if systemctl start "$service" 2>/dev/null; then
            log "OK: Successfully started $service"
        else
            log "ERROR: Failed to start $service"
            failed_services+=("$service")
        fi
    fi
done

# Report results
if [[ ${#failed_services[@]} -gt 0 ]]; then
    log "WARNING: Some services failed to start: ${failed_services[*]}"
    exit 1
else
    log "PASSED: All critical services are running"
    exit 0
fi
