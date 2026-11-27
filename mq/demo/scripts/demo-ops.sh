#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Ishanti MQ Demo Operations Helper
# Run from your laptop against kc1 (169.48.154.115) for repeatable live demos.
# =============================================================================

MQ_HOST="${MQ_HOST:-169.48.154.115}"
MQ_USER="${MQ_USER:-danutek}"
QMGR_NHA="${QMGR_NHA:-MYQMGR}"
QMGR_RDQM="${QMGR_RDQM:-QM1}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

remote() {
  ssh "${SSH_OPTS[@]}" "${MQ_USER}@${MQ_HOST}" "$@"
}

usage() {
  cat <<EOF
Usage: $0 <command> [args]

Commands:
  status                 Side-by-side status of RDQM (${QMGR_RDQM}) and Native HA (${QMGR_NHA})
  verify-queues          List ISHANTI.* queues & channels on ${QMGR_NHA}
  put-test [QUEUE]       Put 3 persistent test messages (default: ISHANTI.DEMO.IN)
  get-test [QUEUE]       Read messages back from queue (default: ISHANTI.DEMO.IN)
  failover [--confirm]   Stop mqmonitor@${QMGR_NHA} on kc1 to trigger failover, then rejoin as Replica
  reset                  Clear test messages, remove ad-hoc demo queues (ISHANTI.ORDERS.*), and re-verify health
EOF
}

cmd_status() {
  remote "
    echo '=================================================================='
    echo '  1. RDQM Queue Manager (${QMGR_RDQM}) — DRBD + Pacemaker'
    echo '=================================================================='
    sudo -n /opt/mqm/bin/rdqmstatus -n
    echo ''
    sudo -n /opt/mqm/bin/rdqmstatus -m '${QMGR_RDQM}'
    echo ''
    echo '--- DRBD Replication ---'
    drbdadm status 2>/dev/null || true
    echo ''
    echo '=================================================================='
    echo '  2. Native HA Queue Manager (${QMGR_NHA}) — Built-in Log Replication'
    echo '=================================================================='
    /opt/mqm/bin/dspmq -m '${QMGR_NHA}' -o nativeha -x
    echo ''
    echo '--- systemd Supervision ---'
    systemctl status 'mqmonitor@${QMGR_NHA}.service' --no-pager -n 5 || true
  "
}

cmd_verify_queues() {
  remote "
    printf \"DIS QLOCAL('ISHANTI.*') CURDEPTH MAXDEPTH DEFPSIST DESCR\nDIS CHANNEL('ISHANTI.*') CHLTYPE\n\" | sudo -n -u mqm /opt/mqm/bin/runmqsc '${QMGR_NHA}'
  "
}

cmd_put_test() {
  local queue="${1:-ISHANTI.DEMO.IN}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Putting 3 persistent test messages to ${queue} on ${QMGR_NHA}..."
  remote "
    printf 'Ishanti Demo Msg 1 (%s)\nIshanti Demo Msg 2 (%s)\nIshanti Demo Msg 3 (%s)\n\n' '${ts}' '${ts}' '${ts}' \
      | sudo -n -u mqm /opt/mqm/samp/bin/amqsput '${queue}' '${QMGR_NHA}'
    echo ''
    printf \"DIS QLOCAL('${queue}') CURDEPTH DEFPSIST\n\" | sudo -n -u mqm /opt/mqm/bin/runmqsc '${QMGR_NHA}'
  "
}

cmd_get_test() {
  local queue="${1:-ISHANTI.DEMO.IN}"
  echo "Reading messages from ${queue} on ${QMGR_NHA}..."
  remote "
    sudo -n -u mqm /opt/mqm/samp/bin/amqsget '${queue}' '${QMGR_NHA}'
    echo ''
    printf \"DIS QLOCAL('${queue}') CURDEPTH\n\" | sudo -n -u mqm /opt/mqm/bin/runmqsc '${QMGR_NHA}'
  "
}

cmd_failover() {
  local confirm="${1:-}"
  if [[ "$confirm" != "--confirm" ]]; then
    cat <<EOF
NOTE: Stopping mqmonitor@${QMGR_NHA} on kc1 will fail over Active to tejas1 or tejas2.
When kc1 restarts, alpha will rejoin as a Replica (and Active will remain on tejas1/tejas2
until you fail it back from that host).

Run this AFTER any kc1-targeted GitHub Actions deploys (or once SSH to tejas1/tejas2 is configured).
To execute live failover now, run:
  $0 failover --confirm
EOF
    return 0
  fi

  echo "=== Before Failover ==="
  remote "/opt/mqm/bin/dspmq -m '${QMGR_NHA}' -o nativeha -x"

  echo ""
  echo "=== Stopping mqmonitor@${QMGR_NHA}.service on kc1 (simulating node outage) ==="
  remote "sudo -n systemctl stop 'mqmonitor@${QMGR_NHA}.service'"
  echo "Waiting 8 seconds for automatic quorum election on tejas1/tejas2..."
  sleep 8

  echo ""
  echo "=== Restarting mqmonitor@${QMGR_NHA}.service on kc1 (rejoining as Replica) ==="
  remote "sudo -n systemctl start 'mqmonitor@${QMGR_NHA}.service'"
  echo "Waiting 8 seconds for log catch-up..."
  sleep 8

  echo ""
  echo "=== After Failover & Rejoin ==="
  remote "/opt/mqm/bin/dspmq -m '${QMGR_NHA}' -o nativeha -x"
}

cmd_reset() {
  echo "Resetting demo state on ${QMGR_NHA} (${MQ_HOST})..."
  remote "
    sudo -n systemctl start 'mqmonitor@${QMGR_NHA}.service'
    sleep 2
    if /opt/mqm/bin/dspmq -m '${QMGR_NHA}' -o all | grep -q 'ROLE(Active)'; then
      printf \"CLEAR QLOCAL('ISHANTI.DEMO.IN')\nCLEAR QLOCAL('ISHANTI.DEMO.OUT')\nCLEAR QLOCAL('ISHANTI.DEMO.DLQ')\nDELETE QLOCAL('ISHANTI.ORDERS.IN') PURGE\n\" \
        | sudo -n -u mqm /opt/mqm/bin/runmqsc '${QMGR_NHA}' || true
    else
      echo 'Note: kc1 is currently Replica; skipping local runmqsc clear.'
    fi
    /opt/mqm/bin/dspmq -m '${QMGR_NHA}' -o nativeha -x
  "
}

case "${1:-}" in
  status)        cmd_status ;;
  verify-queues) cmd_verify_queues ;;
  put-test)      cmd_put_test "${2:-ISHANTI.DEMO.IN}" ;;
  get-test)      cmd_get_test "${2:-ISHANTI.DEMO.IN}" ;;
  failover)      cmd_failover "${2:-}" ;;
  reset)         cmd_reset ;;
  *)             usage; exit 1 ;;
esac
