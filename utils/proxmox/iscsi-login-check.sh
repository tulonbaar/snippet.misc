#!/bin/bash
# Script for checking and logging iSCSI sessions
# Runs at system startup
# Logs results to /var/log/iscsi-login-check.log
# Exit codes:
#   0 - Success
#   1 - Error during execution
# Script assumes iscsiadm is installed and configured, and is run with root privileges

LOG_FILE="/var/log/iscsi-login-check.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "=== Starting iSCSI session check ==="

# Check if iscsiadm is available
if ! command -v iscsiadm &> /dev/null; then
    log_message "ERROR: iscsiadm is not installed"
    exit 1
fi

# Check if iSCSI nodes are defined
NODE_COUNT=$(iscsiadm -m node -o show 2>/dev/null | grep "^node.name" | wc -l)
if [ "$NODE_COUNT" -eq 0 ]; then
    log_message "WARN: No configured iSCSI nodes found"
    exit 0
fi

log_message "Found $NODE_COUNT configured iSCSI nodes"

# Check active sessions
ACTIVE_SESSIONS=$(iscsiadm -m session 2>/dev/null | wc -l)
log_message "Active sessions: $ACTIVE_SESSIONS"

# If the number of active sessions is less than nodes, login all
if [ "$ACTIVE_SESSIONS" -lt "$NODE_COUNT" ]; then
    log_message "Logging in iSCSI sessions (active: $ACTIVE_SESSIONS, expected: $NODE_COUNT)"
    
    # Login all nodes
    if iscsiadm -m node --loginall=all >> "$LOG_FILE" 2>&1; then
        FINAL_SESSIONS=$(iscsiadm -m session 2>/dev/null | wc -l)
        log_message "SUCCESS: Sessions logged in. Active sessions: $FINAL_SESSIONS"
    else
        log_message "ERROR: Error during session login"
        exit 1
    fi
else
    log_message "INFO: All sessions are already active"
fi

log_message "=== Completed iSCSI session check ==="
exit 0
