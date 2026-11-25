#!/bin/bash
# Project: StreamSage Intelligent Transaction Processing Platform
# Purpose: Run all validation checks in sequence

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "StreamSage — Full Validation Suite"
echo "========================================"
echo ""

run() {
    local script=$1
    echo "▶ Running: $script"
    echo "----------------------------------------"
    bash "$SCRIPT_DIR/$script"
    echo ""
}

run "validate-yaml.sh"
run "validate-kustomize.sh"
run "validate-resources.sh"
run "validate-network-policies.sh"
run "validate-pre-deploy.sh" --skip-cluster-check

echo "========================================"
echo "✅ All checks completed successfully"
echo "========================================"
