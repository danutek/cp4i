#!/usr/bin/env bash
set -eu

# Supply the entitlement key through the environment; do not store it here.
oc create secret docker-registry ibm-entitlement-key \
    --docker-username=cp \
    --docker-password="${IBM_ENTITLEMENT_KEY:?Set IBM_ENTITLEMENT_KEY before running this script}" \
    --docker-server=cp.icr.io
