#!/bin/bash
# Project: StreamSage Intelligent Transaction Processing Platform
# Purpose: Validate all Kustomize overlays can be built successfully

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TOTAL=0
PASSED=0
FAILED=0

echo "========================================="
echo "Kustomize Validation — StreamSage"
echo "========================================="
echo ""

validate_overlay() {
    local overlay_path=$1
    local overlay_name=$2

    TOTAL=$((TOTAL + 1))
    echo -n "Validating $overlay_name... "

    if oc kustomize "$overlay_path" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo "  Error details:"
        oc kustomize "$overlay_path" 2>&1 | sed 's/^/    /'
        FAILED=$((FAILED + 1))
        return 1
    fi
}

COMPONENTS=(
    "event-streams"
    "kafka-connect"
    "kafka-topics"
    "kafka-users"
    "kafka-bridge"
    "monitoring"
    "network-policies"
)

for component in "${COMPONENTS[@]}"; do
    echo "Validating $component overlays..."
    echo "-----------------------------------"
    for env in dev test qa staging eem ep perf prod dr; do
        overlay_path="$REPO_ROOT/deploy/apps/overlays/$env/$component"
        if [ -d "$overlay_path" ]; then
            validate_overlay "$overlay_path" "$env/$component"
        else
            echo -e "${YELLOW}⚠ Skipping $env/$component (directory not found)${NC}"
        fi
    done
    echo ""
done

echo "========================================="
echo "Validation Summary"
echo "========================================="
echo "Total overlays validated: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
    echo -e "${RED}❌ Kustomize validation FAILED${NC}"
    exit 1
else
    echo "Failed: $FAILED"
    echo -e "${GREEN}✅ All Kustomize validations PASSED${NC}"
    exit 0
fi
