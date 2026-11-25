#!/bin/bash
# Rolling restart of a Native HA queue manager after Argo CD has synced a change.
#
# The StatefulSet uses updateStrategy OnDelete (required for Native HA), so Kubernetes will not
# restart the pods by itself. This script deletes the pods one at a time, replicas first and the
# active pod last, and waits for the queue manager to be INSYNC with 3/3 QUORUM after each one.
#
# Based on IBM's sample ibm-messaging/mq-helm samples/genericresources/rollingupdate/demoRollingUpdate.sh
# (Apache-2.0). Test it in dev before relying on it elsewhere.
#
# Usage: scripts/rolling-restart.sh <statefulset-name> <namespace>
#   e.g. scripts/rolling-restart.sh qmname-ibm-mq mq-dev
# Set AUTO_ACCEPT=true to skip the confirmation prompt.
set -euo pipefail

sts=${1:?statefulset name}
ns=${2:?namespace}
auto=${AUTO_ACCEPT:-false}
timeout_attempts=60        # 60 x 10s = 10 minutes per pod

# Pods of this StatefulSet, and the one that is Ready (the active queue manager)
all_pods=()
while IFS= read -r p; do [ -n "$p" ] && all_pods+=("$p"); done < <(kubectl get pods -n "$ns" -l "statefulSetName=$sts" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
active=$(kubectl get pods -n "$ns" -l "statefulSetName=$sts" \
  -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' | head -n1)

[ "${#all_pods[@]}" -eq 3 ] || { echo "Expected 3 pods for $sts, found ${#all_pods[@]}. Aborting."; exit 1; }
[ -n "$active" ] || { echo "No active (Ready) pod found. Aborting."; exit 1; }

verify() {
  local pod=$1 attempt=0 out insync quorum
  while true; do
    out=$(kubectl exec -n "$ns" "$pod" -c qmgr -- dspmq -o nativeha 2>/dev/null || true)
    insync=$(sed -n 's/.*INSYNC(\([a-z]*\)).*/\1/p' <<<"$out")
    quorum=$(sed -n 's/.*QUORUM(\([0-9/]*\)).*/\1/p' <<<"$out")
    if [ "$insync" = "yes" ] && [ "$quorum" = "3/3" ]; then
      echo "  $pod: INSYNC(yes) QUORUM(3/3)"; return
    fi
    attempt=$((attempt+1))
    if [ "$attempt" -gt "$timeout_attempts" ]; then
      echo "  $pod did not reach INSYNC(yes) QUORUM(3/3) within 10 minutes (last: ${out:-none}). Stopping."
      exit 1
    fi
    sleep 10
  done
}

recycle() {
  local pod=$1 attempt=0
  kubectl delete pod -n "$ns" "$pod" --wait=true
  until [ "$(kubectl get pod -n "$ns" "$pod" -o jsonpath='{.status.containerStatuses[0].started}' 2>/dev/null)" = "true" ]; do
    attempt=$((attempt+1))
    if [ "$attempt" -gt "$timeout_attempts" ]; then
      echo "  $pod did not start within 10 minutes. Stopping; manual recovery may be needed."
      exit 1
    fi
    sleep 10
  done
}

echo "Pods: ${all_pods[*]}"
echo "Active: $active (restarted last)"
if [ "$auto" != "true" ]; then
  read -r -p "Type 'accept' to continue: " reply
  [ "$reply" = "accept" ] || { echo "Cancelled."; exit 1; }
fi

verify "$active"        # do not start unless the queue manager is healthy now

for pod in "${all_pods[@]}"; do
  [ "$pod" = "$active" ] && continue
  echo "Recycling replica $pod"
  recycle "$pod"
  verify "$active"
done

echo "Recycling active pod $active (causes one failover)"
recycle "$active"
new_active=$(kubectl get pods -n "$ns" -l "statefulSetName=$sts" \
  -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' | head -n1)
verify "${new_active:-$active}"
echo "Done. Active pod is now: ${new_active:-unknown}"
