#!/bin/bash
# StreamSage YAML Validation Script
# Validates all YAML files in the deploy directory for syntax errors

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TOTAL_FILES=0
VALID_FILES=0
INVALID_FILES=0

echo "=========================================="
echo "StreamSage YAML Validation"
echo "=========================================="
echo ""

# Function to validate a single YAML file
validate_yaml() {
    local file=$1
    TOTAL_FILES=$((TOTAL_FILES + 1))
    
    # Skip files in .git directory
    if [[ "$file" == *".git"* ]]; then
        return 0
    fi
    
    # Try to parse the YAML file
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $file"
        VALID_FILES=$((VALID_FILES + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $file"
        echo -e "${RED}  Error:${NC} Invalid YAML syntax"
        python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>&1 | sed 's/^/  /'
        INVALID_FILES=$((INVALID_FILES + 1))
        return 1
    fi
}

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is required but not installed${NC}"
    exit 1
fi

# Check if PyYAML is available
if ! python3 -c "import yaml" 2>/dev/null; then
    echo -e "${YELLOW}Warning: PyYAML not installed. Installing...${NC}"
    pip3 install pyyaml
fi

# Find and validate all YAML files
echo "Scanning for YAML files..."
echo ""

# Validate files in apps directory
if [ -d "deploy/apps" ]; then
    echo "Validating apps directory..."
    while IFS= read -r -d '' file; do
        validate_yaml "$file"
    done < <(find deploy/apps -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)
fi

# Validate files in clusters directory
if [ -d "deploy/clusters" ]; then
    echo ""
    echo "Validating clusters directory..."
    while IFS= read -r -d '' file; do
        validate_yaml "$file"
    done < <(find deploy/clusters -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)
fi

# Print summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "Total files:   $TOTAL_FILES"
echo -e "${GREEN}Valid files:   $VALID_FILES${NC}"
if [ $INVALID_FILES -gt 0 ]; then
    echo -e "${RED}Invalid files: $INVALID_FILES${NC}"
else
    echo -e "Invalid files: $INVALID_FILES"
fi
echo ""

# Exit with error if any files are invalid
if [ $INVALID_FILES -gt 0 ]; then
    echo -e "${RED}❌ Validation failed!${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All YAML files are valid!${NC}"
    exit 0
fi


