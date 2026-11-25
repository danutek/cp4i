#!/bin/bash
# Project: StreamSage Intelligent Transaction Processing Platform
# Purpose: Update namespace references across overlay kustomization.yaml files
#          Rewrites any namespace: kafka-es-{env} pattern to namespace: kafka-{env}

set -e

echo "Updating overlay namespaces to 'kafka-{env}' pattern..."
echo ""

ENVIRONMENTS=("dev" "test" "qa" "staging" "eem" "ep" "perf" "prod" "dr")
COMPONENTS=("event-streams" "kafka-connect" "kafka-users" "kafka-topics" "kafka-bridge" "monitoring" "network-policies")

for env in "${ENVIRONMENTS[@]}"; do
    echo "Processing environment: $env"
    for component in "${COMPONENTS[@]}"; do
        kustomization_file="deploy/apps/overlays/$env/$component/kustomization.yaml"
        if [ -f "$kustomization_file" ]; then
            # Replace kafka-es-{env} or kafka-{env} variants to canonical kafka-{env}
            sed -i.bak "s/^namespace: kafka-es-${env}$/namespace: kafka-${env}/" "$kustomization_file"
            sed -i.bak "s/^namespace: kafka-es$/namespace: kafka-${env}/" "$kustomization_file"
            rm -f "${kustomization_file}.bak"
            echo "  ✓ $kustomization_file"
        else
            echo "  - skipping $component (not found)"
        fi
    done
done

echo ""
echo "✅ Namespace update complete!"
echo "  Pattern applied: namespace: kafka-{env}"
echo "  Environments:    ${ENVIRONMENTS[*]}"
echo "  Components:      ${COMPONENTS[*]}"
