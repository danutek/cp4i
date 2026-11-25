#!/bin/bash
# Project: StreamSage Intelligent Transaction Processing Platform
# Purpose: Validate NetworkPolicies are correctly applied in a namespace

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NAMESPACE=${1:-kafka-dev}
TIMEOUT=5

echo "=========================================="
echo "NetworkPolicy Validation — StreamSage"
echo "Namespace: $NAMESPACE"
echo "=========================================="
echo ""

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info()    { echo "ℹ $1"; }

check_namespace() {
    print_info "Checking if namespace exists..."
    if oc get namespace "$NAMESPACE" &> /dev/null; then
        print_success "Namespace $NAMESPACE exists"
    else
        print_error "Namespace $NAMESPACE does not exist"
        return 1
    fi
}

check_policies_exist() {
    print_info "Checking NetworkPolicy resources..."
    local policies=(
        "default-deny-all"
        "kafka-broker-policy"
        "kafka-connect-policy"
        "kafka-bridge-policy"
        "grafana-policy"
    )
    local all_exist=true
    for policy in "${policies[@]}"; do
        if oc get networkpolicy "$policy" -n "$NAMESPACE" &> /dev/null; then
            print_success "NetworkPolicy $policy exists"
        else
            print_warning "NetworkPolicy $policy not found (may not be deployed yet)"
            all_exist=false
        fi
    done
    [ "$all_exist" = true ]
}

check_pod_labels() {
    print_info "Checking pod labels match NetworkPolicy selectors..."
    local kafka_pods
    kafka_pods=$(oc get pods -n "$NAMESPACE" -l strimzi.io/kind=Kafka --no-headers 2>/dev/null | wc -l)
    [ "$kafka_pods" -gt 0 ] && print_success "Found $kafka_pods Kafka broker pods" \
                            || print_warning "No Kafka broker pods found"

    local connect_pods
    connect_pods=$(oc get pods -n "$NAMESPACE" -l strimzi.io/kind=KafkaConnect --no-headers 2>/dev/null | wc -l)
    [ "$connect_pods" -gt 0 ] && print_success "Found $connect_pods Kafka Connect pods" \
                               || print_warning "No Kafka Connect pods found"

    local bridge_pods
    bridge_pods=$(oc get pods -n "$NAMESPACE" -l strimzi.io/kind=KafkaBridge --no-headers 2>/dev/null | wc -l)
    [ "$bridge_pods" -gt 0 ] && print_success "Found $bridge_pods Kafka Bridge pods" \
                              || print_warning "No Kafka Bridge pods found"
}

test_dns_resolution() {
    print_info "Testing DNS resolution from Kafka pods..."
    local test_pod
    test_pod=$(oc get pods -n "$NAMESPACE" -l strimzi.io/kind=Kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$test_pod" ]; then
        print_warning "No Kafka pods found to test DNS resolution"
        return 0
    fi
    if oc exec -n "$NAMESPACE" "$test_pod" -c kafka -- nslookup kubernetes.default &> /dev/null; then
        print_success "DNS resolution working from $test_pod"
    else
        print_error "DNS resolution failed from $test_pod"
        return 1
    fi
}

cleanup() {
    print_info "Cleaning up test resources..."
    oc delete pod test-client -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
}

main() {
    local exit_code=0

    check_namespace || exit_code=1
    echo ""
    check_policies_exist || exit_code=1
    echo ""
    oc get networkpolicies -n "$NAMESPACE" -o wide 2>/dev/null || true
    echo ""
    check_pod_labels
    echo ""
    test_dns_resolution || exit_code=1
    echo ""
    cleanup

    echo "=========================================="
    if [ $exit_code -eq 0 ]; then
        print_success "All NetworkPolicy validations passed!"
    else
        print_error "Some NetworkPolicy validations failed"
    fi
    echo "=========================================="
    exit $exit_code
}

main
