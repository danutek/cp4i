#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Apply Declarative MQSC to Native HA Queue Manager (MYQMGR) over SSH
#
# Supports single host (MQ_HOST) or comma-separated host list (MQ_HOSTS) to
# automatically locate the node running ROLE(Active).
# =============================================================================

QMGR="${QMGR:-MYQMGR}"
MQSC_FILE="${MQSC_FILE:-mq/demo/myqmgr.mqsc}"
MQ_USER="${MQ_USER:-danutek}"
MQ_HOSTS="${MQ_HOSTS:-${MQ_HOST:-169.48.154.115}}"
SSH_KEY_FILE="${SSH_KEY_FILE:-}"
DRY_RUN="${DRY_RUN:-false}"

if [[ ! -f "$MQSC_FILE" ]]; then
  echo "ERROR: MQSC file not found: $MQSC_FILE" >&2
  exit 1
fi

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
if [[ -n "$SSH_KEY_FILE" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY_FILE")
fi

# Locate which host currently holds ROLE(Active) for QMGR
ACTIVE_HOST=""
LAST_STATUS=""

IFS=',' read -r -a HOST_LIST <<< "$MQ_HOSTS"
for host in "${HOST_LIST[@]}"; do
  host="$(echo "$host" | xargs)"
  [[ -z "$host" ]] && continue
  echo "Checking Native HA role on ${MQ_USER}@${host} for ${QMGR}..."
  if status_out=$(ssh "${SSH_OPTS[@]}" "${MQ_USER}@${host}" "/opt/mqm/bin/dspmq -m '${QMGR}' -o all" 2>&1); then
    LAST_STATUS="$status_out"
    if echo "$status_out" | grep -q "ROLE(Active)" && echo "$status_out" | grep -q "STATUS(Running)"; then
      ACTIVE_HOST="$host"
      echo "Found Active instance of ${QMGR} on ${ACTIVE_HOST}."
      break
    else
      echo "Host ${host} is not Active: ${status_out}"
    fi
  else
    echo "Warning: could not query ${host}: ${status_out}" >&2
  fi
done

if [[ -z "$ACTIVE_HOST" ]]; then
  echo "ERROR: Could not locate a Running Active instance of ${QMGR} across [${MQ_HOSTS}]." >&2
  if [[ -n "$LAST_STATUS" ]]; then
    echo "Last status observed: ${LAST_STATUS}" >&2
  fi
  echo "Tip: If failover moved Active to tejas1 or tejas2, include their SSH hosts in MQ_HOSTS or fail back to kc1." >&2
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY_RUN=true: Skipping runmqsc apply. Verifying current Native HA health on ${ACTIVE_HOST}..."
else
  echo "Applying ${MQSC_FILE} to ${QMGR} on ${ACTIVE_HOST}..."
  APPLY_OUT="$(ssh "${SSH_OPTS[@]}" "${MQ_USER}@${ACTIVE_HOST}" "sudo -n -u mqm /opt/mqm/bin/runmqsc '${QMGR}'" < "$MQSC_FILE" 2>&1)"
  echo "$APPLY_OUT"

  # Fail on MQSC errors (AMQ*E / AMQ*S) or processing failures
  if echo "$APPLY_OUT" | grep -Eq "^AMQ[0-9]+[ES]:|could not be processed|^(One|[0-9]+) commands? ha(s|ve) a syntax error"; then
    echo "ERROR: MQSC application reported errors on ${ACTIVE_HOST}." >&2
    exit 1
  fi
  if ! echo "$APPLY_OUT" | grep -q "No commands have a syntax error." || ! echo "$APPLY_OUT" | grep -q "All valid MQSC commands were processed."; then
    echo "ERROR: MQSC output did not confirm clean execution on ${ACTIVE_HOST}." >&2
    exit 1
  fi
fi

echo ""
echo "=== Post-Deploy Verification: Native HA Quorum & Sync ==="
NHA_OUT="$(ssh "${SSH_OPTS[@]}" "${MQ_USER}@${ACTIVE_HOST}" "/opt/mqm/bin/dspmq -m '${QMGR}' -o nativeha -x" 2>&1)"
echo "$NHA_OUT"

if ! echo "$NHA_OUT" | grep -q "QUORUM(3/3)"; then
  echo "WARNING: Native HA quorum is not 3/3! Review instance status above." >&2
  exit 1
fi

if ! echo "$NHA_OUT" | grep -q "INSYNC(yes)"; then
  echo "ERROR: Native HA group is not in sync!" >&2
  exit 1
fi

echo ""
echo "=== Deployed VANGUARD.* Objects on ${QMGR} (replicated to all 3 nodes) ==="
OBJ_OUT="$(ssh "${SSH_OPTS[@]}" "${MQ_USER}@${ACTIVE_HOST}" "printf \"DIS QLOCAL('VANGUARD.*') CURDEPTH MAXDEPTH DEFPSIST\nDIS CHANNEL('VANGUARD.*') CHLTYPE\n\" | sudo -n -u mqm /opt/mqm/bin/runmqsc '${QMGR}'" 2>&1)"
echo "$OBJ_OUT"

# Append structured summary when running inside GitHub Actions
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Native HA Deployment Summary (\`${QMGR}\`)"
    echo ""
    echo "- **Target Active Host:** \`${ACTIVE_HOST}\`"
    echo "- **MQSC File:** \`${MQSC_FILE}\`"
    echo "- **Dry Run:** \`${DRY_RUN}\`"
    echo "- **Quorum Gate:** Passed (\`QUORUM(3/3)\`, \`INSYNC(yes)\`)"
    echo ""
    echo "### Native HA Group Status"
    echo '```text'
    echo "$NHA_OUT"
    echo '```'
    echo ""
    echo "### Deployed Objects"
    echo '```text'
    echo "$OBJ_OUT"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "Done: ${QMGR} updated and verified healthy across all 3 Native HA instances."
