#!/bin/bash
# =============================================================================
# LINKSAFE Pre-Reboot Hook: Drain Connections
# =============================================================================
# Gracefully drain connections before reboot (customize for your environment)
# Exit 0 = continue with reboot, Exit non-zero = abort reboot
# =============================================================================

set -euo pipefail

# Configuration - customize for your environment
DRAIN_ENABLED="${DRAIN_ENABLED:-false}"
DRAIN_WAIT_SECONDS="${DRAIN_WAIT_SECONDS:-30}"
LOAD_BALANCER_API="${LOAD_BALANCER_API:-}"
NODE_ID="${NODE_ID:-$(hostname)}"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [HOOK:drain-connections] $1"
}

log "Preparing for reboot..."

# If drain is disabled, skip
if [[ "$DRAIN_ENABLED" != "true" ]]; then
    log "INFO: Connection draining is disabled (DRAIN_ENABLED=false)"
    exit 0
fi

# Example: Remove from load balancer
if [[ -n "$LOAD_BALANCER_API" ]]; then
    log "Removing node from load balancer..."

    # Customize this for your load balancer
    # Example with curl:
    # curl -X POST "${LOAD_BALANCER_API}/nodes/${NODE_ID}/drain" \
    #     -H "Content-Type: application/json" \
    #     -d '{"drain": true}'

    log "INFO: Load balancer API configured but not implemented"
    log "INFO: Customize this hook for your environment"
fi

# Wait for connections to drain
log "Waiting ${DRAIN_WAIT_SECONDS} seconds for connections to drain..."
sleep "$DRAIN_WAIT_SECONDS"

# Example: Check for active connections
active_connections=$(ss -tn state established 2>/dev/null | wc -l || echo "0")
log "INFO: ${active_connections} active connections remaining"

log "PASSED: Connection drain completed"
exit 0
