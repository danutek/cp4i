#!/usr/bin/env bash
# StreamSage Cluster Bootstrap Script
#
# Usage:
#   export IBM_ENTITLEMENT_KEY="..."
#   export ARGOCD_REPO_TOKEN="..."
#   ./deploy/scripts/bootstrap-cluster.sh [ENV_CODE ...]
#
# ENV_CODE is a 3-letter environment code. Pass one or more codes to bootstrap
# only those environments. Defaults to 'dev' if no codes are given.
#
#   Code  Full name
#   ----  ---------
#   dev   dev
#   tst   test
#   qa    qa
#   stg   staging
#   prf   perf
#   prd   prod
#   ep    ep
#   eem   eem
#   dr    dr
#
# Examples:
#   ./bootstrap-cluster.sh               # dev only (default)
#   ./bootstrap-cluster.sh dev           # dev only (explicit)
#   ./bootstrap-cluster.sh dev tst prf   # dev, test, perf
#   ./bootstrap-cluster.sh dev tst qa stg prf prd ep eem dr  # all 9 envs
#
# See docs/event-streams/BOOTSTRAP_PREREQUISITES.md for full prerequisites.
#
# This script is idempotent — safe to re-run on an existing cluster.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ============================================================================
# Helpers
# ============================================================================

log()  { echo "[bootstrap] $*"; }
info() { echo "[bootstrap] ✓ $*"; }
fail() { echo "[bootstrap] ✗ $*" >&2; exit 1; }

require_env() {
  local var="$1"
  [[ -n "${!var:-}" ]] || fail "Required environment variable \$$var is not set. See docs/event-streams/BOOTSTRAP_PREREQUISITES.md"
}

wait_for() {
  local description="$1" max_seconds="$2"
  shift 2
  local cmd="$*"
  log "Waiting for ${description} (up to ${max_seconds}s)..."
  local elapsed=0
  while ! eval "$cmd" >/dev/null 2>&1; do
    if (( elapsed >= max_seconds )); then
      log "  Warning: ${description} timed out after ${max_seconds}s — check manually before proceeding"
      return 1
    fi
    sleep 10
    (( elapsed += 10 ))
  done
  info "${description} ready"
}

# Resolve a 3-letter env code to its full name.
# Prints the full name on stdout; exits 1 if the code is unknown.
resolve_env_code() {
  local code="$1"
  case "$code" in
    dev) echo "dev"     ;;
    tst) echo "test"    ;;
    qa)  echo "qa"      ;;
    stg) echo "staging" ;;
    prf) echo "perf"    ;;
    prd) echo "prod"    ;;
    ep)  echo "ep"      ;;
    eem) echo "eem"     ;;
    dr)  echo "dr"      ;;
    *)
      echo "[bootstrap] ✗ Unknown environment code: '${code}'" >&2
      echo "[bootstrap]   Valid codes: dev tst qa stg prf prd ep eem dr" >&2
      exit 1
      ;;
  esac
}

# ============================================================================
# Environment selection — resolve positional args to full env names
# ============================================================================

INPUT_CODES=("${@:-dev}")   # default to dev if no args given

SELECTED_ENVS=()
for code in "${INPUT_CODES[@]}"; do
  full="$(resolve_env_code "$code")"
  SELECTED_ENVS+=("$full")
done

log "Environments selected: ${SELECTED_ENVS[*]}"

# ============================================================================
# 0. Preflight checks
# ============================================================================

log "Verifying prerequisites..."
command -v oc >/dev/null 2>&1 || fail "'oc' is not installed or not on PATH"
oc whoami >/dev/null 2>&1    || fail "Not logged in to an OpenShift cluster. Run 'oc login' first."
require_env IBM_ENTITLEMENT_KEY
require_env ARGOCD_REPO_TOKEN
info "Preflight checks passed (logged in as: $(oc whoami))"

# ============================================================================
# 1. IBM Entitlement Key — MUST be first (required before catalog pod can pull)
# ============================================================================

log "Step 1: Creating IBM Entitlement Key secret in openshift-marketplace..."
oc get namespace openshift-marketplace >/dev/null 2>&1 || \
  oc create namespace openshift-marketplace

oc create secret docker-registry ibm-entitlement-key \
  --namespace=openshift-marketplace \
  --docker-server=icr.io \
  --docker-username=cp \
  --docker-password="${IBM_ENTITLEMENT_KEY}" \
  --dry-run=client -o yaml | oc apply -f -

info "ibm-entitlement-key secret created/updated in openshift-marketplace"

# ============================================================================
# 1b. PostgreSQL superuser secret (required by CloudNativePG initdb)
#     Only created for selected environments.
# ============================================================================

log "Step 1b: Creating PostgreSQL superuser secrets for selected environments..."
PGPASSWORD="${POSTGRES_SUPERUSER_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=')}"

for env in "${SELECTED_ENVS[@]}"; do
  ns="postgres-${env}"
  oc get namespace "$ns" >/dev/null 2>&1 || continue
  oc create secret generic streamsage-postgres-superuser \
    --namespace="$ns" \
    --from-literal=username=postgres \
    --from-literal=password="${PGPASSWORD}" \
    --dry-run=client -o yaml | oc apply -f -
  info "streamsage-postgres-superuser secret created/updated in ${ns}"
done

# ============================================================================
# 2a. Create namespaces for selected environments
#
#     Each environment gets three namespaces: kafka-{env}, streamsage-{env},
#     postgres-{env}. We create them directly (not via the full base kustomization)
#     so only the selected envs land on the cluster. ArgoCD's cluster-config
#     Application will reconcile labels and annotations once it syncs.
# ============================================================================

log "Step 2a: Creating namespaces for selected environments..."

for env in "${SELECTED_ENVS[@]}"; do
  for prefix in kafka streamsage postgres; do
    ns="${prefix}-${env}"
    oc create namespace "$ns" \
      --dry-run=client -o yaml | oc apply -f -
    info "Namespace ${ns} created/confirmed"
  done
done

# ============================================================================
# 2b. Apply IBM operator catalog
# ============================================================================

log "Step 2b: Applying IBM operator catalog..."
oc apply -f "${REPO_ROOT}/deploy/clusters/cluster-config/catalogs/ibm-operator-catalog.yaml"
info "IBM operator catalog applied"

# ============================================================================
# 2c. Apply operator subscriptions
# ============================================================================

log "Step 2c: Applying operator subscriptions..."
oc apply -k "${REPO_ROOT}/deploy/clusters/cluster-config/operator/"
info "Operator subscriptions applied"

# ============================================================================
# 3. Wait for OpenShift GitOps operator to install and create ArgoCD instance
# ============================================================================

log "Step 3: Waiting for OpenShift GitOps operator..."
wait_for "openshift-gitops namespace" 300 \
  "oc get namespace openshift-gitops >/dev/null 2>&1"

wait_for "ArgoCD instance" 300 \
  "oc get argocd openshift-gitops -n openshift-gitops >/dev/null 2>&1"

# Approve the GitOps install plan if it requires manual approval
GITOPS_IP=$(oc get installplan -n openshift-operators \
  -l operators.coreos.com/openshift-gitops-operator.openshift-operators= \
  -o name 2>/dev/null | head -1)
if [[ -n "$GITOPS_IP" ]]; then
  oc patch "$GITOPS_IP" -n openshift-operators \
    --type merge -p '{"spec":{"approved":true}}' 2>/dev/null || true
  info "Approved GitOps install plan"
fi

# ============================================================================
# 4. Register this repository with ArgoCD
# ============================================================================

log "Step 4: Registering repository with ArgoCD..."
REPO_URL=$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null \
  || echo "https://github.ibm.com/danutek/StreamSage.git")

oc apply -n openshift-gitops -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: streamsage-repo
  namespace: openshift-gitops
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: "${REPO_URL}"
  password: "${ARGOCD_REPO_TOKEN}"
  username: git
EOF
info "Repository registered: ${REPO_URL}"

# ============================================================================
# 5. Apply ArgoCD Projects
# ============================================================================

log "Step 5: Applying ArgoCD Projects..."
oc apply -f "${REPO_ROOT}/deploy/apps/argocd/projects/" -n openshift-gitops
info "ArgoCD Projects applied"

# ============================================================================
# 6. Apply ArgoCD ApplicationSets (ArgoCD takes over all further deployment)
# ============================================================================

log "Step 6: Applying ArgoCD ApplicationSets..."
for appset in "${REPO_ROOT}"/deploy/apps/argocd/applicationsets/*.yaml; do
  oc apply -f "$appset" -n openshift-gitops
  info "Applied $(basename "$appset")"
done

# ============================================================================
# 7. Approve CloudNativePG and Event Streams install plans (Manual approval)
# ============================================================================

log "Step 7: Approving operator install plans (Manual approval mode)..."

for ns in openshift-operators ibm-eventstreams; do
  for ip in $(oc get installplan -n "$ns" -o name 2>/dev/null); do
    APPROVED=$(oc get "$ip" -n "$ns" -o jsonpath='{.spec.approved}' 2>/dev/null || echo "true")
    if [[ "$APPROVED" == "false" ]]; then
      oc patch "$ip" -n "$ns" --type merge -p '{"spec":{"approved":true}}'
      info "Approved $ip in $ns"
    fi
  done
done

# ============================================================================
# Done
# ============================================================================

echo ""
echo "========================================================================"
echo "  StreamSage cluster bootstrap complete."
echo "  Environments bootstrapped: ${SELECTED_ENVS[*]}"
echo ""
echo "  ArgoCD is now managing the cluster. Monitor progress:"
echo "    oc get applications -n openshift-gitops"
for env in "${SELECTED_ENVS[@]}"; do
  echo "    oc get pods -n streamsage-${env} -w"
done
echo ""
echo "  Run the pre-deploy validator to confirm readiness:"
echo "    ./deploy/scripts/validate-pre-deploy.sh ${INPUT_CODES[*]}"
echo "========================================================================"
