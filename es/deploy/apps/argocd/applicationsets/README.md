# StreamSage ArgoCD ApplicationSets

This directory contains ApplicationSet definitions that automatically generate ArgoCD Applications for all environments using the Git Generator pattern.

## Overview

ApplicationSets eliminate the need for individual Application YAML files by automatically discovering environments and generating applications dynamically.

**Benefits:**
- ✅ Automatic environment discovery
- ✅ Consistent configuration across all environments
- ✅ Reduced configuration from ~30 files to 6 ApplicationSets
- ✅ No manual Application creation for new environments

## ApplicationSets

### 1. Event Streams (`event-streams-appset.yaml`)
Deploys IBM Event Streams Kafka clusters across all environments.

**Generated Applications:**
- `test-event-streams`
- `prod-event-streams`
- `dr-event-streams`
- `dev-event-streams` (when dev overlay is created)
- `qa-event-streams` (when qa overlay is created)
- etc.

### 2. Kafka Connect (`kafka-connect-appset.yaml`)
Deploys Kafka Connect clusters for data integration with JDBC connectors.

### 3. Kafka Topics (`kafka-topics-appset.yaml`)
Manages StreamSage-specific Kafka topics:
- `streamsage.ingest.transaction`
- `streamsage.transaction.event`
- `streamsage.transaction.family.event`
- `streamsage.ai.event`
- `streamsage.approval.event`
- `streamsage.attachment.event`
- `streamsage.audit.event`
- `streamsage.notification.event`
- `streamsage.workflow.event`
- `streamsage.deadletter`

### 4. StreamSage Console (`streamsage-console-appset.yaml`)
Deploys the StreamSage web console (Next.js application).

### 5. Cluster Configuration (`cluster-config-appset.yaml`)
Deploys cluster-wide resources (namespaces, operators, storage classes, catalogs).

### 6. Network Policies (`network-policies-appset.yaml`)
Deploys NetworkPolicies for zero-trust network security and microsegmentation.

**Generated Applications:**
- `dev-network-policies`
- `test-network-policies`
- `prod-network-policies`
- etc.

**Resources Managed:**
- Default deny-all NetworkPolicy (blocks all traffic by default)
- Kafka broker NetworkPolicy (allows Kafka-specific traffic)
- Kafka Connect NetworkPolicy (allows Connect cluster traffic)
- StreamSage services NetworkPolicy (allows service-to-service communication)
- StreamSage console NetworkPolicy (allows web console access)
- PostgreSQL NetworkPolicy (allows database access)

**Security Features:**
- Zero-trust architecture with default deny
- Microsegmentation between components
- Explicit allow rules for required communication
- Lateral movement prevention

## How It Works

### Git Generator Pattern

Each ApplicationSet uses the **Git Generator** to automatically discover environments:

```yaml
generators:
  - git:
      repoURL: https://github.ibm.com/danutek/StreamSage.git
      revision: HEAD
      directories:
        - path: deploy/apps/overlays/*
```

This generator:
1. Scans the repository for directories matching the pattern
2. Extracts the environment name from the directory path
3. Generates an Application for each discovered environment
4. Uses Go templating to customize each Application

## Adding a New Environment

To add a new environment (e.g., "staging"):

1. Create the overlay directory structure:
   ```bash
   mkdir -p deploy/apps/overlays/staging/{event-streams,kafka-connect,kafka-topics,streamsage-console,network-policies}
   ```

2. Create `kustomization.yaml` files in each component directory

3. Commit and push changes

4. ApplicationSets will **automatically** generate Applications for the new environment

**No manual Application creation needed!**

## Deployment

### Apply All ApplicationSets

```bash
# Apply all ApplicationSets
oc apply -f deploy/apps/argocd/applicationsets/

# Verify ApplicationSets are created
oc get applicationsets -n openshift-gitops

# Check generated Applications
oc get applications -n openshift-gitops
```

### Apply Individual ApplicationSet

```bash
# Deploy only Event Streams ApplicationSet
oc apply -f deploy/apps/argocd/applicationsets/event-streams-appset.yaml

# Verify applications generated
oc get applications -n openshift-gitops -l component=event-streams
```

## Monitoring

### View Generated Applications

```bash
# List all applications
oc get applications -n openshift-gitops

# Filter by environment
oc get applications -n openshift-gitops -l environment=test

# Filter by component
oc get applications -n openshift-gitops -l component=event-streams

# Get application details
oc describe application test-event-streams -n openshift-gitops
```

### Check Sync Status

```bash
# Using oc
oc get applications -n openshift-gitops -o wide

# Using argocd CLI
argocd app list
argocd app get test-event-streams
```

## Troubleshooting

### ApplicationSet Not Generating Applications

1. **Check ApplicationSet status:**
   ```bash
   oc get applicationset -n openshift-gitops event-streams -o yaml
   ```

2. **Verify directory structure matches pattern:**
   ```bash
   ls -la deploy/apps/overlays/*/event-streams/
   ```

3. **Check ArgoCD logs:**
   ```bash
   oc logs -n openshift-gitops -l app.kubernetes.io/name=argocd-applicationset-controller
   ```

### Application Sync Failures

1. **Check Application status:**
   ```bash
   oc describe application test-event-streams -n openshift-gitops
   ```

2. **View sync errors:**
   ```bash
   argocd app get test-event-streams
   ```

3. **Check Kustomize build:**
   ```bash
   oc kustomize deploy/apps/overlays/test/event-streams
   ```

## References

- [ArgoCD ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Git Generator Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)
- [StreamSage Migration Guide](../../MIGRATION_GUIDE.md)