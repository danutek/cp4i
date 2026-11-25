#!/bin/bash
# ==============================================================================
# Script Name: rdqm_health_check.sh
# Purpose:     Automated Daily Health Report for IBM MQ RDQM
# Organization: ExampleCo
# ==============================================================================

# Configuration
HOSTNAME=$(hostname)
DATE=$(date '+%Y-%m-%d %H:%M:%S')
REPORT_FILE="/var/log/rdqm_daily_health_${HOSTNAME}_$(date '+%Y%m%d').log"
# EMAIL_TO="mq-admins@example.com" # Uncomment and configure mailx to send emails

# Start Report
{
    echo "========================================================================="
    echo " IBM MQ RDQM Daily Health Report "
    echo " Node: $HOSTNAME "
    echo " Date: $DATE "
    echo "========================================================================="
    echo ""

    echo "--- 1. High-Level RDQM Status ---"
    /opt/mqm/bin/rdqmstatus 2>&1
    echo ""

    echo "--- 2. Pacemaker Cluster Status ---"
    # Runs crm_mon once and exits cleanly
    crm_mon -1 2>&1
    echo ""

    echo "--- 3. DRBD Replication Status ---"
    cat /proc/drbd 2>&1
    echo ""

    echo "--- 4. Core Services Status ---"
    echo -n "Pacemaker Service: "
    systemctl is-active pacemaker || echo "INACTIVE/FAILED"
    echo -n "Corosync Service:  "
    systemctl is-active corosync || echo "INACTIVE/FAILED"
    echo ""

    echo "--- 5. Kernel Module Status (Secure Boot/DRBD) ---"
    DRBD_MODS=$(lsmod | grep drbd)
    if [ -z "$DRBD_MODS" ]; then
        echo "WARNING: DRBD kernel modules are NOT loaded!"
    else
        echo "DRBD modules loaded successfully:"
        echo "$DRBD_MODS"
    fi
    echo ""

    echo "========================================================================="
    echo " End of Report "
    echo "========================================================================="

} > "$REPORT_FILE"

# Optional: Send email report
# if [ -n "$EMAIL_TO" ]; then
#     mail -s "RDQM Health Report - $HOSTNAME - $(date '+%Y-%m-%d')" "$EMAIL_TO" < "$REPORT_FILE"
# fi

# Keep only the last 14 days of local logs to prevent disk fill-up
find /var/log/ -name "rdqm_daily_health_*.log" -type f -mtime +14 -exec rm {} \;

exit 0
