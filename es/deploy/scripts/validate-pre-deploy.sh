#!/usr/bin/env bash
# StreamSage Pre-Deploy Validation Script
#
# Verifies that the cluster and local environment are ready for a StreamSage deploy.
# Exit code 0 = all checks passed.  Non-zero = one or more checks failed.
#
# Usage:
#   ./deploy/scripts/validate-pre-deploy.sh [ENV_CODE ...]
#
# Pass the same ENV_CODE arguments you used with bootstrap-cluster.sh.
# Defaults to 'dev' if no codes are given.
#
#   Code  Full name     Code  Full name
#   ----  ---------     ----  ---------
#   dev   dev           prd   prod
#   tst   test          ep    ep
#   qa    qa            eem   eem
#   stg   staging       dr    dr
#   prf   perf

set -uo pipefail

PASS=0
FAIL=0

pass() { echo "  [PASS] $*"; ((PASS++)); }
fail() { echo "  [FAIL] $*"; ((FAIL++)); }
section() { echo ""; echo "── $* ──────────────────────────────────────────"; }

# ============================================================================
# Environment selection — same resolver as bootstrap-cluster.sh
# ============================================================================

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
      echo "  [FAIL] Unknown environment code: '${code}'"
      echo "         Valid codes: dev tst qa stg prf prd ep eem dr"
      exit 1
      ;;
  esac
}

INPUT_CODES=("${@:-dev}")

SELECTED_ENVS=()
for code in "${INPUT_CODES[@]}"; do
  full="$(resolve_env_code "$code")"
  SELECTED_ENVS+=("$full")
done

echo "StreamSage Pre-Deploy Validation"
echo "================================="
echo "  Environments: ${SELECTED_ENVS[*]}"

# ============================================================================
section "OpenShift CLI"
# ============================================================================

if command -v oc >/dev/null 2>&1; then
  pass "oc is installed: $(oc version --client 2>/dev/null | head -1)"
else
  fail "oc is not installed or not on PATH"
fi

if oc whoami >/dev/null 2>&1; then
  pass "Logged in as: $(oc whoami)"
  pass "Cluster: $(oc cluster-info 2>/dev/null | head -1 | sed 's/.*running at //')"
else
  fail "Not authenticated to an OpenShift cluster — run 'oc login' first"
fi

# ============================================================================
section "IBM Entitlement Key"
# ============================================================================

if [[ -n "${IBM_ENTITLEMENT_KEY:-}" ]]; then
  pass "\$IBM_ENTITLEMENT_KEY is set"
else
  fail "\$IBM_ENTITLEMENT_KEY is not set — required for IBM operator catalog"
fi

if oc get secret ibm-entitlement-key -n openshift-marketplace >/dev/null 2>&1; then
  pass "ibm-entitlement-key secret exists in openshift-marketplace"
else
  fail "ibm-entitlement-key secret NOT found in openshift-marketplace"
  echo "       Run: deploy/scripts/bootstrap-cluster.sh to create it"
fi

# ============================================================================
section "StreamSage Namespaces (selected environments)"
# ============================================================================

for env in "${SELECTED_ENVS[@]}"; do
  ns="streamsage-${env}"
  if oc get namespace "$ns" >/dev/null 2>&1; then
    pass "Namespace $ns exists"
  else
    fail "Namespace $ns does not exist"
  fi
done

# ============================================================================
section "ArgoCD (OpenShift GitOps)"
# ============================================================================

if oc get namespace openshift-gitops >/dev/null 2>&1; then
  pass "openshift-gitops namespace exists"
else
  fail "openshift-gitops namespace not found — OpenShift GitOps not installed"
fi

if oc get argocd openshift-gitops -n openshift-gitops >/dev/null 2>&1; then
  pass "ArgoCD instance 'openshift-gitops' is present"
else
  fail "ArgoCD instance not found"
fi

# ============================================================================
section "CloudNativePG Operator"
# ============================================================================

if oc get crd clusters.postgresql.cnpg.io >/dev/null 2>&1; then
  pass "CloudNativePG CRD (Cluster) is registered"
else
  fail "CloudNativePG CRD not found — operator may not be installed"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "========================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then
  echo "  Address the failed checks before deploying."
  echo "  See docs/event-streams/BOOTSTRAP_PREREQUISITES.md for guidance."
  exit 1
fi

echo "  All checks passed — ready to deploy."
exit 0
