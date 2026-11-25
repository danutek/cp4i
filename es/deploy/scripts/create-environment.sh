#!/bin/bash
# Project: StreamSage Intelligent Transaction Processing Platform
# Purpose: Create a new environment overlay structure for all Kafka components

set -e

ENV_NAME=$1
BROKERS=${2:-3}
CONTROLLERS=${3:-3}
STORAGE=${4:-100Gi}
CPU=${5:-1}
MEMORY=${6:-8Gi}

if [ -z "$ENV_NAME" ]; then
    echo "Usage: $0 <env-name> [brokers] [controllers] [storage] [cpu] [memory]"
    echo "Example: $0 qa 3 3 100Gi 1 8Gi"
    exit 1
fi

BASE_DIR="deploy/apps/overlays/${ENV_NAME}"
NS="kafka-${ENV_NAME}"

echo "Creating environment: $ENV_NAME"
echo "  Namespace:   $NS"
echo "  Brokers:     $BROKERS"
echo "  Controllers: $CONTROLLERS"
echo "  Storage:     $STORAGE"
echo "  CPU:         $CPU"
echo "  Memory:      $MEMORY"
echo ""

# Create all component directories
mkdir -p "${BASE_DIR}/event-streams"
mkdir -p "${BASE_DIR}/kafka-connect"
mkdir -p "${BASE_DIR}/kafka-users"
mkdir -p "${BASE_DIR}/kafka-topics"
mkdir -p "${BASE_DIR}/kafka-bridge"
mkdir -p "${BASE_DIR}/monitoring"
mkdir -p "${BASE_DIR}/network-policies"

# ── event-streams ──────────────────────────────────────────────────────────────
cat > "${BASE_DIR}/event-streams/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NS}

bases:
  - ../../../base/event-streams

patches:
  - path: kafka-es-patch.yaml

commonLabels:
  environment: ${ENV_NAME}
  app.kubernetes.io/instance: kafka-${ENV_NAME}
  app.kubernetes.io/part-of: streamsage
EOF

cat > "${BASE_DIR}/event-streams/kafka-es-patch.yaml" <<EOF
apiVersion: eventstreams.ibm.com/v1beta2
kind: EventStreams
metadata:
  name: es
spec:
  strimziOverrides:
    nodePools:
      - name: broker
        replicas: ${BROKERS}
        storage:
          type: persistent-claim
          class: portworx-sc-repl-3
          size: ${STORAGE}
          deleteClaim: false
        roles:
          - broker
        resources:
          requests:
            cpu: "${CPU}"
            memory: ${MEMORY}
          limits:
            cpu: "${CPU}"
            memory: ${MEMORY}
      - name: controller
        replicas: ${CONTROLLERS}
        storage:
          type: persistent-claim
          class: portworx-sc-repl-3
          size: 20Gi
          deleteClaim: false
        roles:
          - controller
        resources:
          requests:
            cpu: "500m"
            memory: 2Gi
          limits:
            cpu: "1"
            memory: 4Gi
EOF

# ── kafka-connect ──────────────────────────────────────────────────────────────
cat > "${BASE_DIR}/kafka-connect/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NS}

bases:
  - ../../../base/kafka-connect

patches:
  - path: kc-patch.yaml

commonLabels:
  environment: ${ENV_NAME}
  app.kubernetes.io/instance: kafka-connect-${ENV_NAME}
  app.kubernetes.io/part-of: streamsage
EOF

cat > "${BASE_DIR}/kafka-connect/kc-patch.yaml" <<EOF
apiVersion: eventstreams.ibm.com/v1beta2
kind: KafkaConnect
metadata:
  name: kc
spec:
  replicas: 2
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 2Gi
EOF

# ── kafka-users ────────────────────────────────────────────────────────────────
cat > "${BASE_DIR}/kafka-users/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NS}

bases:
  - ../../../base/kafka-users

commonLabels:
  environment: ${ENV_NAME}
  app.kubernetes.io/instance: kafka-users-${ENV_NAME}
  app.kubernetes.io/part-of: streamsage
EOF

# ── kafka-topics ───────────────────────────────────────────────────────────────
cat > "${BASE_DIR}/kafka-topics/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NS}

bases:
  - ../../../base/kafka-topics

commonLabels:
  environment: ${ENV_NAME}
  app.kubernetes.io/instance: kafka-topics-${ENV_NAME}
  app.kubernetes.io/part-of: streamsage
EOF

# ── kafka-bridge ───────────────────────────────────────────────────────────────
cat > "${BASE_DIR}/kafka-bridge/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NS}

bases:
  - ../../../base/kafka-bridge

patches:
  - path: kafka-bridge-patch.yaml

commonLabels:
  environment: ${ENV_NAME}
  app.kubernetes.io/instance: kafka-bridge-${ENV_NAME}
  app.kubernetes.io/part-of: streamsage
EOF

cat > "${BASE_DIR}/kafka-bridge/kafka-bridge-patch.yaml" <<EOF
apiVersion: eventstreams.ibm.com/v1beta2
kind: KafkaBridge
metadata:
  name: kafka-bridge
spec:
  replicas: 1
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi
EOF

# ── monitoring ─────────────────────────────────────────────────────────────────
cat > "${BASE_DIR}/monitoring/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NS}

bases:
  - ../../../base/monitoring

commonLabels:
  environment: ${ENV_NAME}
  app.kubernetes.io/instance: kafka-monitoring-${ENV_NAME}
  app.kubernetes.io/part-of: streamsage
EOF

# ── network-policies ───────────────────────────────────────────────────────────
cat > "${BASE_DIR}/network-policies/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NS}

resources:
  - ../../../base/network-policies

commonLabels:
  environment: ${ENV_NAME}
  app.kubernetes.io/instance: network-policies-${ENV_NAME}
  app.kubernetes.io/part-of: streamsage
EOF

echo "✅ Environment '${ENV_NAME}' created successfully!"
echo ""
echo "Created directories:"
echo "  ${BASE_DIR}/event-streams"
echo "  ${BASE_DIR}/kafka-connect"
echo "  ${BASE_DIR}/kafka-users"
echo "  ${BASE_DIR}/kafka-topics"
echo "  ${BASE_DIR}/kafka-bridge"
echo "  ${BASE_DIR}/monitoring"
echo "  ${BASE_DIR}/network-policies"
echo ""
echo "The new overlays will be automatically picked up by the ArgoCD ApplicationSets."
echo "Commit and push to trigger deployment."
