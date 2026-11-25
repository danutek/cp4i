#!/bin/bash
# StreamSage Master Validation Script
# Runs all validation checks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED_VALIDATIONS=0

echo "=========================================="
echo "StreamSage Complete Validation Suite"
echo "=========================================="
echo ""

# Function to run a validation script
run_validation() {
    local script=$1
    local name=$2
    
    echo -e "${BLUE}Running: $name${NC}"
    echo "=========================================="
    
    if bash "$SCRIPT_DIR/$script"; then
        echo -e "${GREEN}✅ $name passed${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}❌ $name failed${NC}"
        echo ""
        FAILED_VALIDATIONS=$((FAILED_VALIDATIONS + 1))
        return 1
    fi
}

# Run all validations
run_validation "validate-yaml.sh" "YAML Syntax Validation" || true
run_validation "validate-kustomize.sh" "Kustomize Build Validation" || true
run_validation "validate-resources.sh" "Resource Configuration Validation" || true

# Print final summary
echo "=========================================="
echo "Final Validation Summary"
echo "=========================================="

if [ $FAILED_VALIDATIONS -eq 0 ]; then
    echo -e "${GREEN}✅ All validations passed!${NC}"
    echo ""
    echo "Your deployment configuration is ready for:"
    echo "  • Committing to Git"
    echo "  • Deploying to clusters"
    echo "  • ArgoCD synchronization"
    exit 0
else
    echo -e "${RED}❌ $FAILED_VALIDATIONS validation(s) failed${NC}"
    echo ""
    echo "Please fix the issues above before:"
    echo "  • Committing to Git"
    echo "  • Deploying to clusters"
    echo "  • ArgoCD synchronization"
    exit 1
fi


