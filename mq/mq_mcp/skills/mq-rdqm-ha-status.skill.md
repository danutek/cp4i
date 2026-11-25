# IBM MQ RDQM High Availability Status Monitoring

## Description
This skill provides comprehensive guidance for monitoring RDQM (Replicated Data Queue Manager) high availability status using both CLI commands and REST API. Essential for ensuring HA cluster health and detecting failover conditions.

## Prerequisites
- RDQM HA cluster configured (3-node setup)
- SSH access to RDQM nodes
- MQ REST API access (see `mq-rest-api-basics.skill.md`)
- Root or mqm user privileges for CLI commands

## RDQM Architecture Overview

### Three-Node HA Cluster
```
Node 1 (Primary)    ←→  Node 2 (Secondary)  ←→  Node 3 (Secondary)
   ↓                        ↓                        ↓
DRBD Replication    DRBD Replication    DRBD Replication
   ↓                        ↓                        ↓
Pacemaker/Corosync Cluster Management
   ↓
Floating IP (Active on Primary)
```

## CLI-Based Monitoring

### Check RDQM Status
```bash
# Check status of specific RDQM
rdqmstatus -m QM1

# Expected output for healthy primary:
# Node:                                   node1
# Queue manager status:                   Running
# CPU:                                    0.00%
# Memory:                                 195MB
# Queue manager file system:              58MB used, 1.5GB allocated [4%]
# HA role:                                Primary
# HA status:                              Normal
# HA control:                             Enabled
# HA current location:                    This node
# HA preferred location:                  This node
# HA floating IP interface:               eth0
# HA floating IP address:                 192.168.1.100

# Check all RDQMs on node
rdqmstatus -m all
```

### Check HA Cluster Status
```bash
# Check RDQM status (includes HA role and cluster info)
rdqmstatus -m QM1

# Check DRBD replication status
drbdadm status

# Expected healthy output:
# rdqm_QM1 role:Primary
#   disk:UpToDate
#   node2 role:Secondary
#     replication:Established peer-disk:UpToDate
#   node3 role:Secondary
#     replication:Established peer-disk:UpToDate

# Check specific RDQM DRBD resource
drbdadm status rdqm_QM1

# View cluster quorum status
rdqmstatus -m QM1 | grep -E "HA status:|HA control:"
```

### Monitor Floating IP
```bash
# Check which node has the floating IP
ip addr show | grep "192.168.1.100"

# Check floating IP from RDQM status
rdqmstatus -m QM1 | grep "HA floating IP"

# Verify floating IP is accessible
ping -c 3 192.168.1.100
```

### Check Replication Lag
```bash
# Check DRBD performance metrics
cat /proc/drbd

# Monitor replication in real-time
watch -n 2 'drbdadm status rdqm_QM1'

# Check for split-brain condition
drbdadm dstate rdqm_QM1
```

## REST API Monitoring

### Get Queue Manager HA Status
```bash
# Set environment
export MQ_REST_HOST="192.168.1.100"  # Floating IP
export MQ_REST_PORT="9443"
export MQ_REST_USER="mqadmin"
export MQ_REST_PASS="secure_password"
export MQ_QMGR_NAME="QM1"

MQ_BASE_URL="https://${MQ_REST_HOST}:${MQ_REST_PORT}/ibmmq/rest/v2/admin"

# Get queue manager status including HA info
curl -sk -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/status" \
  | jq '.'

# Expected response includes:
# {
#   "qmgr": [{
#     "name": "QM1",
#     "status": "running",
#     "haStatus": "normal",
#     "haRole": "primary",
#     "haPreferredLocation": "node1",
#     "haCurrentLocation": "node1"
#   }]
# }
```

### Monitor Multiple RDQMs
```bash
# Check status of all queue managers
curl -sk -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr?status=*" \
  | jq -r '.qmgr[] | "\(.name): \(.status) - HA: \(.haStatus) (\(.haRole))"'
```

## Automated Health Checks

### Comprehensive RDQM Health Check Script
```bash
#!/bin/bash
# rdqm_health_check.sh

QMGR_NAME="QM1"
FLOATING_IP="192.168.1.100"
ALERT_EMAIL="admin@example.com"

echo "=== RDQM Health Check: $(date) ==="

# 1. Check RDQM status
echo -e "\n1. RDQM Status:"
RDQM_STATUS=$(rdqmstatus -m ${QMGR_NAME})
echo "$RDQM_STATUS"

# Extract key values
HA_ROLE=$(echo "$RDQM_STATUS" | grep "HA role:" | awk '{print $3}')
HA_STATUS=$(echo "$RDQM_STATUS" | grep "HA status:" | awk '{print $3}')
QM_STATUS=$(echo "$RDQM_STATUS" | grep "Queue manager status:" | awk '{print $4}')

# 2. Check DRBD replication
echo -e "\n2. DRBD Replication Status:"
DRBD_STATUS=$(drbdadm status rdqm_${QMGR_NAME})
echo "$DRBD_STATUS"

# 3. Check HA cluster status via RDQM
echo -e "\n3. HA Cluster Status:"
HA_STATUS=$(rdqmstatus -m ${QMGR_NAME} | grep -E "HA status:|HA control:|HA role:")
echo "$HA_STATUS"

# 4. Check floating IP
echo -e "\n4. Floating IP Check:"
if ping -c 1 -W 2 ${FLOATING_IP} > /dev/null 2>&1; then
  echo "✓ Floating IP ${FLOATING_IP} is reachable"
else
  echo "✗ Floating IP ${FLOATING_IP} is NOT reachable"
  echo "ALERT: Floating IP unreachable" | mail -s "RDQM Alert: ${QMGR_NAME}" ${ALERT_EMAIL}
fi

# 5. Health assessment
echo -e "\n5. Health Assessment:"
HEALTHY=true

if [ "$QM_STATUS" != "Running" ]; then
  echo "✗ Queue manager is not running"
  HEALTHY=false
fi

if [ "$HA_STATUS" != "Normal" ]; then
  echo "✗ HA status is not normal: ${HA_STATUS}"
  HEALTHY=false
fi

if echo "$DRBD_STATUS" | grep -q "Inconsistent\|StandAlone"; then
  echo "✗ DRBD replication issue detected"
  HEALTHY=false
fi

if [ "$HEALTHY" = true ]; then
  echo "✓ All checks passed - RDQM is healthy"
  exit 0
else
  echo "✗ Health check failed - issues detected"
  exit 1
fi
```

### Monitor Replication Lag
```bash
#!/bin/bash
# check_replication_lag.sh

QMGR_NAME="QM1"
MAX_LAG_MB=100  # Alert if lag exceeds 100MB

# Get DRBD statistics
DRBD_STATS=$(drbdsetup status rdqm_${QMGR_NAME} --statistics --verbose)

# Extract out-of-sync data
OOS_BYTES=$(echo "$DRBD_STATS" | grep "out-of-sync:" | awk '{print $2}')
OOS_MB=$((OOS_BYTES / 1024 / 1024))

echo "Replication lag: ${OOS_MB} MB"

if [ ${OOS_MB} -gt ${MAX_LAG_MB} ]; then
  echo "WARNING: Replication lag (${OOS_MB} MB) exceeds threshold (${MAX_LAG_MB} MB)"
  exit 1
fi

echo "Replication lag is within acceptable limits"
exit 0
```

## Failover Detection

### Detect Failover Events
```bash
# Monitor for failover in real-time
watch -n 5 'rdqmstatus -m QM1 | grep "HA current location"'

# Check Pacemaker logs for failover events
journalctl -u pacemaker -f | grep -i "failover\|migrate"

# Check MQ error logs for failover
tail -f /var/mqm/qmgrs/${QMGR_NAME}/errors/AMQERR01.LOG | grep -i "failover\|takeover"
```

### Failover History
```bash
# Check Pacemaker logs for failover events
journalctl -u pacemaker --since "1 day ago" | grep -i "failover\|migrate\|takeover"

# Check DRBD events
drbdadm events2 rdqm_${QMGR_NAME} --statistics --now

# Parse MQ logs for failover timestamps
grep -i "failover\|takeover" /var/mqm/qmgrs/${QMGR_NAME}/errors/AMQERR*.LOG

# Check RDQM status changes over time
journalctl -u rdqm --since "1 day ago" | grep -i "status change\|role change"
```

## Performance Metrics

### Collect RDQM Metrics
```bash
# CPU and Memory usage
rdqmstatus -m ${QMGR_NAME} | grep -E "CPU:|Memory:"

# Filesystem usage
rdqmstatus -m ${QMGR_NAME} | grep "file system:"

# DRBD I/O statistics
drbdsetup status rdqm_${QMGR_NAME} --statistics | grep -E "read:|written:|al-writes:"
```

### REST API Metrics Collection
```bash
# Collect metrics via REST API
curl -sk -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/status" \
  | jq '{
    name: .qmgr[0].name,
    status: .qmgr[0].status,
    haRole: .qmgr[0].haRole,
    haStatus: .qmgr[0].haStatus,
    connectionCount: .qmgr[0].connectionCount,
    timestamp: now | strftime("%Y-%m-%d %H:%M:%S")
  }' >> rdqm_metrics.jsonl
```

## Alerting Scenarios

### Critical Alerts
```bash
# 1. Queue manager stopped
if [ "$QM_STATUS" != "Running" ]; then
  echo "CRITICAL: Queue manager ${QMGR_NAME} is not running"
fi

# 2. HA status not normal
if [ "$HA_STATUS" != "Normal" ]; then
  echo "CRITICAL: HA status is ${HA_STATUS}"
fi

# 3. Split-brain detected
if drbdadm dstate rdqm_${QMGR_NAME} | grep -q "StandAlone"; then
  echo "CRITICAL: DRBD split-brain detected"
fi

# 4. Floating IP not responding
if ! ping -c 1 -W 2 ${FLOATING_IP} > /dev/null 2>&1; then
  echo "CRITICAL: Floating IP ${FLOATING_IP} unreachable"
fi
```

### Warning Alerts
```bash
# 1. Replication lag high
if [ ${OOS_MB} -gt 50 ]; then
  echo "WARNING: High replication lag: ${OOS_MB} MB"
fi

# 2. Filesystem usage high
FS_USAGE=$(rdqmstatus -m ${QMGR_NAME} | grep "file system:" | grep -oP '\[\K[0-9]+')
if [ ${FS_USAGE} -gt 80 ]; then
  echo "WARNING: Filesystem usage at ${FS_USAGE}%"
fi

# 3. Node not preferred location
CURRENT_LOC=$(rdqmstatus -m ${QMGR_NAME} | grep "HA current location:" | awk '{print $4}')
PREFERRED_LOC=$(rdqmstatus -m ${QMGR_NAME} | grep "HA preferred location:" | awk '{print $4}')
if [ "$CURRENT_LOC" != "$PREFERRED_LOC" ]; then
  echo "WARNING: QM running on non-preferred node"
fi
```

## Multi-Node Monitoring

### Check Status Across All Nodes
```bash
#!/bin/bash
# check_all_nodes.sh

NODES=("node1" "node2" "node3")
QMGR_NAME="QM1"

for NODE in "${NODES[@]}"; do
  echo "=== Checking ${NODE} ==="
  ssh ${NODE} "rdqmstatus -m ${QMGR_NAME} 2>&1" || echo "Failed to connect to ${NODE}"
  echo ""
done
```

### Cluster-Wide Health Dashboard
```bash
#!/bin/bash
# rdqm_dashboard.sh

clear
while true; do
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║         RDQM HA Cluster Status - $(date +%H:%M:%S)         ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  
  # Queue Manager Status
  echo -e "\n📊 Queue Manager: ${QMGR_NAME}"
  rdqmstatus -m ${QMGR_NAME} | grep -E "status:|HA role:|HA status:|HA current location:"
  
  # DRBD Status
  echo -e "\n💾 DRBD Replication:"
  drbdadm status rdqm_${QMGR_NAME} | head -5
  
  # HA Cluster Status
  echo -e "\n🔧 Cluster Status:"
  rdqmstatus -m ${QMGR_NAME} | grep -E "HA status:|HA control:|HA role:"
  
  # Floating IP
  echo -e "\n🌐 Floating IP:"
  ip addr show | grep "${FLOATING_IP}" || echo "Not on this node"
  
  sleep 5
  clear
done
```

## Integration with MCP Server

An MCP server can use these monitoring capabilities to:

1. **Automated Health Checks**
   - Poll RDQM status across all nodes
   - Detect failover events in real-time
   - Alert on replication issues

2. **Centralized Monitoring**
   - Aggregate status from multiple RDQM clusters
   - Track failover history and patterns
   - Generate health reports

3. **Proactive Management**
   - Predict failover based on metrics
   - Recommend maintenance windows
   - Validate HA configuration consistency

4. **Incident Response**
   - Automated diagnostics on alerts
   - Collect logs and metrics for troubleshooting
   - Coordinate failback operations

## Troubleshooting Commands

### Common Issues

```bash
# DRBD not syncing
drbdadm disconnect rdqm_${QMGR_NAME}
drbdadm connect rdqm_${QMGR_NAME}

# Force a manual failover to a specific node (Changes preferred node)
setmqm -m ${QMGR_NAME} -n node2

# Stop a queue manager immediately if it's hung (forces failover)
endmqm -i ${QMGR_NAME}

# Suspend a node from the cluster (for maintenance)
rdqmadm -s

# Resume a suspended node
rdqmadm -r

# View detailed Pacemaker/HA logs (to see quorum and failover events)
journalctl -u pacemaker -f

# View RDQM specific error logs
tail -f /var/mqm/qmgrs/${QMGR_NAME}/errors/AMQERR01.LOG
```

**Note:** In the latest versions of MQ RDQM, the Pacemaker cluster is embedded and managed through RDQM commands. Direct `pcs` commands are no longer available or recommended. The cluster uses quorum-based self-fencing instead of STONITH for split-brain protection.

## Best Practices

1. **Regular Monitoring** - Check status every 5 minutes
2. **Baseline Metrics** - Establish normal replication lag
3. **Alert Thresholds** - Set appropriate warning/critical levels
4. **Failover Testing** - Test failover monthly
5. **Log Retention** - Keep 30 days of metrics
6. **Documentation** - Document all failover events

## Related Skills
- `mq-rest-api-basics.skill.md` - REST API fundamentals
- `mq-queue-management.skill.md` - Queue operations
- `mq-channel-management.skill.md` - Channel monitoring
- `rdqm-failover-procedures.skill.md` - Failover operations

## References
- [RDQM HA Documentation](https://www.ibm.com/docs/en/ibm-mq/latest?topic=multiplatforms-rdqm-high-availability)
- [DRBD Administration Guide](https://linbit.com/drbd-user-guide/)
- [Pacemaker Documentation](https://clusterlabs.org/pacemaker/doc/)