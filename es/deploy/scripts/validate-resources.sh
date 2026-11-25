#!/bin/bash
# StreamSage Resource Validation Script
# Validates Kubernetes resource configurations for best practices

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
WARNING_CHECKS=0
FAILED_CHECKS=0

echo "=========================================="
echo "StreamSage Resource Validation"
echo "=========================================="
echo ""

# Function to check resource limits
check_resource_limits() {
    local file=$1
    local resource_type=$2
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if grep -q "resources:" "$file" && grep -q "limits:" "$file"; then
        echo -e "${GREEN}✓${NC} Resource limits defined in $file"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${YELLOW}⚠${NC} Missing resource limits in $file"
        WARNING_CHECKS=$((WARNING_CHECKS + 1))
    fi
}

# Function to check security context
check_security_context() {
    local file=$1
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if grep -q "securityContext:" "$file"; then
        echo -e "${GREEN}✓${NC} Security context defined in $file"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        
        # Check for runAsNonRoot
        if grep -q "runAsNonRoot: true" "$file"; then
            echo -e "${GREEN}  ✓${NC} runAsNonRoot enabled"
        else
            echo -e "${YELLOW}  ⚠${NC} runAsNonRoot not enabled"
        fi
    else
        echo -e "${YELLOW}⚠${NC} Missing security context in $file"
        WARNING_CHECKS=$((WARNING_CHECKS + 1))
    fi
}

# Function to check liveness and readiness probes
check_probes() {
    local file=$1
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    local has_liveness=$(grep -c "livenessProbe:" "$file" || true)
    local has_readiness=$(grep -c "readinessProbe:" "$file" || true)
    
    if [ $has_liveness -gt 0 ] && [ $has_readiness -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Health probes defined in $file"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    elif [ $has_liveness -gt 0 ] || [ $has_readiness -gt 0 ]; then
        echo -e "${YELLOW}⚠${NC} Incomplete health probes in $file"
        WARNING_CHECKS=$((WARNING_CHECKS + 1))
    else
        echo -e "${YELLOW}⚠${NC} Missing health probes in $file"
        WARNING_CHECKS=$((WARNING_CHECKS + 1))
    fi
}

# Function to check replica count
check_replicas() {
    local file=$1
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if grep -q "replicas:" "$file"; then
        local replicas=$(grep "replicas:" "$file" | head -1 | awk '{print $2}')
        if [ "$replicas" -ge 2 ]; then
            echo -e "${GREEN}✓${NC} High availability configured (replicas: $replicas) in $file"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
        else
            echo -e "${YELLOW}⚠${NC} Single replica configured in $file"
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
        fi
    fi
}

# Function to check storage configuration
check_storage() {
    local file=$1
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if grep -q "storage:" "$file"; then
        local storage=$(grep "storage:" "$file" | head -1 | awk '{print $2}')
        echo -e "${GREEN}✓${NC} Storage configured ($storage) in $file"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        
        # Check for storage class
        if grep -q "storageClassName:" "$file"; then
            echo -e "${GREEN}  ✓${NC} Storage class specified"
        else
            echo -e "${YELLOW}  ⚠${NC} Storage class not specified (will use default)"
        fi
    fi
}

# Function to check namespace
check_namespace() {
    local file=$1
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if grep -q "namespace:" "$file"; then
        local namespace=$(grep "namespace:" "$file" | head -1 | awk '{print $2}')
        echo -e "${GREEN}✓${NC} Namespace specified ($namespace) in $file"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${YELLOW}⚠${NC} Namespace not specified in $file"
        WARNING_CHECKS=$((WARNING_CHECKS + 1))
    fi
}

# Function to check labels
check_labels() {
    local file=$1
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if grep -q "labels:" "$file"; then
        echo -e "${GREEN}✓${NC} Labels defined in $file"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        
        # Check for recommended labels
        local has_app=$(grep -c "app:" "$file" || true)
        local has_version=$(grep -c "version:" "$file" || true)
        local has_component=$(grep -c "component:" "$file" || true)
        
        if [ $has_app -eq 0 ]; then
            echo -e "${YELLOW}  ⚠${NC} Missing 'app' label"
        fi
    else
        echo -e "${YELLOW}⚠${NC} No labels defined in $file"
        WARNING_CHECKS=$((WARNING_CHECKS + 1))
    fi
}

echo "Validating Deployment resources..."
echo ""

# Check Deployments
if [ -d "deploy/apps" ]; then
    while IFS= read -r -d '' file; do
        if grep -q "kind: Deployment" "$file"; then
            echo -e "${BLUE}Checking Deployment:${NC} $(basename $file)"
            check_resource_limits "$file" "Deployment"
            check_security_context "$file"
            check_probes "$file"
            check_replicas "$file"
            check_namespace "$file"
            check_labels "$file"
            echo ""
        fi
    done < <(find deploy/apps -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)
fi

echo "Validating StatefulSet resources..."
echo ""

# Check StatefulSets
if [ -d "deploy/apps" ]; then
    while IFS= read -r -d '' file; do
        if grep -q "kind: StatefulSet" "$file"; then
            echo -e "${BLUE}Checking StatefulSet:${NC} $(basename $file)"
            check_resource_limits "$file" "StatefulSet"
            check_security_context "$file"
            check_probes "$file"
            check_replicas "$file"
            check_storage "$file"
            check_namespace "$file"
            check_labels "$file"
            echo ""
        fi
    done < <(find deploy/apps -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)
fi

echo "Validating Kafka resources..."
echo ""

# Check EventStreams
if [ -d "deploy/apps" ]; then
    while IFS= read -r -d '' file; do
        if grep -q "kind: EventStreams" "$file" || grep -q "kind: Kafka" "$file"; then
            echo -e "${BLUE}Checking Kafka cluster:${NC} $(basename $file)"
            check_replicas "$file"
            check_storage "$file"
            check_namespace "$file"
            echo ""
        fi
    done < <(find deploy/apps -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)
fi

# Check KafkaConnect
if [ -d "deploy/apps" ]; then
    while IFS= read -r -d '' file; do
        if grep -q "kind: KafkaConnect" "$file"; then
            echo -e "${BLUE}Checking Kafka Connect:${NC} $(basename $file)"
            check_replicas "$file"
            check_namespace "$file"
            echo ""
        fi
    done < <(find deploy/apps -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)
fi

# Print summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "Total checks:    $TOTAL_CHECKS"
echo -e "${GREEN}Passed:          $PASSED_CHECKS${NC}"
echo -e "${YELLOW}Warnings:        $WARNING_CHECKS${NC}"
echo -e "${RED}Failed:          $FAILED_CHECKS${NC}"
echo ""

# Calculate percentage
if [ $TOTAL_CHECKS -gt 0 ]; then
    PASS_PERCENTAGE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    echo -e "Pass rate: ${PASS_PERCENTAGE}%"
    echo ""
fi

# Exit with warning if there are warnings but no failures
if [ $FAILED_CHECKS -gt 0 ]; then
    echo -e "${RED}❌ Validation failed!${NC}"
    exit 1
elif [ $WARNING_CHECKS -gt 0 ]; then
    echo -e "${YELLOW}⚠ Validation passed with warnings${NC}"
    exit 0
else
    echo -e "${GREEN}✅ All resource validations passed!${NC}"
    exit 0
fi


