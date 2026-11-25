# StreamSage Application Sets

This document describes the ArgoCD ApplicationSets configured for automated deployment of StreamSage components across all environments.

## Overview

StreamSage uses ArgoCD ApplicationSets to automatically deploy applications across multiple environments using a GitOps approach. Each ApplicationSet monitors the Git repository and automatically creates ArgoCD Applications for each environment overlay it discovers.

## Application Sets

### 1. StreamSage Console (`streamsage-console-appset.yaml`)

**Purpose**: Deploys the StreamSage frontend console application

**Components**:
- Next.js-based web application
- User interface for transaction management
- Dashboard and analytics views

**Deployment Pattern**:
- Monitors: `deploy/apps/overlays/*/streamsage-console`
- Creates applications for: dev, test, qa, staging, perf, prod, ep, eem, dr
- Namespace pattern: `streamsage-{environment}`

**Resources**:
- Deployment with configurable replicas per environment
- Service (ClusterIP)
- Route (OpenShift) for external access

### 2. StreamSage Services (`streamsage-services-appset.yaml`)

**Purpose**: Deploys all backend microservices

**Components**:
1. **API Gateway** - Main API entry point
2. **Ingest Service** - Transaction ingestion from Kafka
3. **Outbox Publisher** - Outbox pattern implementation
4. **Event Monitor** - Event monitoring and visualization
5. **Transaction Service** - Core transaction processing
6. **TX Family Service** - Family relationship management
7. **Workflow Service** - Workflow orchestration
8. **Context Service** - Context management
9. **Notification Service** - Notification handling

**Deployment Pattern**:
- Monitors: `deploy/apps/overlays/*/streamsage-services`
- Creates applications for: dev, test, qa, staging, perf, prod, ep, eem, dr
- Namespace pattern: `streamsage-{environment}`

**Resources per Service**:
- Deployment with environment-specific replicas
- Service (ClusterIP)
- ConfigMap for configuration
- Secret for sensitive data

## Environment Configuration

### Replica Scaling by Environment

| Environment | Console Replicas | Service Replicas | Purpose |
|-------------|------------------|------------------|---------|
| dev         | 1                | 1                | Development |
| test        | 1                | 1                | Automated testing |
| qa          | 2                | 2                | QA validation |
| staging     | 3                | 3                | Pre-production |
| perf        | 3                | 3                | Performance testing |
| prod        | 3                | 3                | Production |
| ep          | 5                | 5                | Enterprise production |
| eem         | 2                | 2                | Enterprise event mgmt |
| dr          | 3                | 3                | Disaster recovery |

### Namespace Structure

Each environment uses dedicated namespaces:
- **Kafka**: `kafka-{environment}` - Event Streams and Kafka components
- **StreamSage**: `streamsage-{environment}` - Application services and console

## Directory Structure

```
deploy/apps/
├── argocd/
│   └── applicationsets/
│       ├── streamsage-console-appset.yaml    # Console ApplicationSet
│       └── streamsage-services-appset.yaml   # Services ApplicationSet
├── base/
│   ├── streamsage-console/                   # Console base manifests
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── route.yaml
│   │   └── kustomization.yaml
│   └── streamsage-services/                  # Services base manifests
│       ├── api-gateway/
│       ├── ingest-service/
│       ├── outbox-publisher/
│       ├── event-monitor/
│       ├── transaction-service/
│       ├── tx-family-service/
│       ├── workflow-service/
│       ├── context-service/
│       ├── notification-service/
│       └── kustomization.yaml
└── overlays/
    ├── dev/
    │   ├── streamsage-console/
    │   └── streamsage-services/
    ├── test/
    │   ├── streamsage-console/
    │   └── streamsage-services/
    ├── qa/
    │   ├── streamsage-console/
    │   └── streamsage-services/
    ├── staging/
    │   ├── streamsage-console/
    │   └── streamsage-services/
    ├── perf/
    │   ├── streamsage-console/
    │   └── streamsage-services/
    ├── prod/
    │   ├── streamsage-console/
    │   └── streamsage-services/
    ├── ep/
    │   ├── streamsage-console/
    │   └── streamsage-services/
    ├── eem/
    │   ├── streamsage-console/
    │   └── streamsage-services/
    └── dr/
        ├── streamsage-console/
        └── streamsage-services/
```

## Deployment Process

### Prerequisites

1. **ArgoCD Installation**
   ```bash
   # ArgoCD should be installed in openshift-gitops namespace
   kubectl get pods -n openshift-gitops
   ```

2. **Git Repository Access**
   - Repository: `https://github.ibm.com/danutek/StreamSage.git`
   - ArgoCD must have read access to the repository

3. **Namespaces**
   - ApplicationSets will automatically create namespaces
   - Alternatively, pre-create them:
   ```bash
   for env in dev test qa staging perf prod ep eem dr; do
     kubectl create namespace streamsage-${env}
     kubectl create namespace kafka-${env}
   done
   ```

### Deploying ApplicationSets

1. **Apply Console ApplicationSet**
   ```bash
   kubectl apply -f deploy/apps/argocd/applicationsets/streamsage-console-appset.yaml
   ```

2. **Apply Services ApplicationSet**
   ```bash
   kubectl apply -f deploy/apps/argocd/applicationsets/streamsage-services-appset.yaml
   ```

3. **Verify ApplicationSet Creation**
   ```bash
   kubectl get applicationsets -n openshift-gitops
   ```

4. **Check Generated Applications**
   ```bash
   kubectl get applications -n openshift-gitops | grep streamsage
   ```

### Expected Applications

After applying both ApplicationSets, you should see 18 applications:

**Console Applications (9)**:
- dev-streamsage-console
- test-streamsage-console
- qa-streamsage-console
- staging-streamsage-console
- perf-streamsage-console
- prod-streamsage-console
- ep-streamsage-console
- eem-streamsage-console
- dr-streamsage-console

**Services Applications (9)**:
- dev-streamsage-services
- test-streamsage-services
- qa-streamsage-services
- staging-streamsage-services
- perf-streamsage-services
- prod-streamsage-services
- ep-streamsage-services
- eem-streamsage-services
- dr-streamsage-services

## Sync Policies

Both ApplicationSets use automated sync with the following policies:

### Automated Sync
- **Prune**: Enabled - Removes resources not in Git
- **Self Heal**: Enabled - Reverts manual changes
- **Allow Empty**: Disabled - Prevents empty applications

### Sync Options
- **CreateNamespace**: true - Auto-creates target namespaces
- **PrunePropagationPolicy**: foreground - Ensures proper deletion order
- **PruneLast**: true - Prunes resources after new ones are healthy

### Retry Policy
- **Limit**: 5 attempts
- **Backoff**:
  - Initial duration: 5s
  - Factor: 2 (exponential backoff)
  - Max duration: 3m

## Monitoring and Management

### View Application Status

```bash
# List all applications
kubectl get applications -n openshift-gitops

# Get detailed status
kubectl describe application dev-streamsage-console -n openshift-gitops

# View sync status
argocd app list | grep streamsage
```

### Manual Sync

```bash
# Sync a specific application
argocd app sync dev-streamsage-console

# Sync all console applications
argocd app sync -l component=streamsage-console

# Sync all services applications
argocd app sync -l component=streamsage-services
```

### View Application in UI

1. Access ArgoCD UI
2. Filter by label: `app.kubernetes.io/part-of=streamsage`
3. Click on application to view details

## Troubleshooting

### Application Not Syncing

1. **Check ApplicationSet**
   ```bash
   kubectl describe applicationset streamsage-console -n openshift-gitops
   kubectl describe applicationset streamsage-services -n openshift-gitops
   ```

2. **Check Application Status**
   ```bash
   kubectl get application dev-streamsage-console -n openshift-gitops -o yaml
   ```

3. **View Sync Errors**
   ```bash
   argocd app get dev-streamsage-console
   ```

### Missing Applications

If applications aren't being generated:

1. **Verify Directory Structure**
   ```bash
   ls -la deploy/apps/overlays/*/streamsage-console
   ls -la deploy/apps/overlays/*/streamsage-services
   ```

2. **Check Git Repository Access**
   ```bash
   argocd repo list
   ```

3. **Refresh ApplicationSet**
   ```bash
   kubectl delete applicationset streamsage-console -n openshift-gitops
   kubectl apply -f deploy/apps/argocd/applicationsets/streamsage-console-appset.yaml
   ```

### Sync Failures

1. **Check Resource Quotas**
   ```bash
   kubectl describe resourcequota -n streamsage-dev
   ```

2. **Check Image Pull**
   ```bash
   kubectl get pods -n streamsage-dev
   kubectl describe pod <pod-name> -n streamsage-dev
   ```

3. **Check Secrets and ConfigMaps**
   ```bash
   kubectl get secrets -n streamsage-dev
   kubectl get configmaps -n streamsage-dev
   ```

## Adding New Environments

To add a new environment:

1. **Create Overlay Directories**
   ```bash
   mkdir -p deploy/apps/overlays/new-env/streamsage-console
   mkdir -p deploy/apps/overlays/new-env/streamsage-services
   ```

2. **Create Console Overlay**
   ```bash
   # Create kustomization.yaml and patches
   # See existing environments for examples
   ```

3. **Create Services Overlay**
   ```bash
   # Create kustomization.yaml and patches
   # See existing environments for examples
   ```

4. **Commit and Push**
   ```bash
   git add deploy/apps/overlays/new-env
   git commit -m "Add new-env environment"
   git push
   ```

5. **Wait for ApplicationSet to Detect**
   - ApplicationSets poll the repository periodically
   - Or manually refresh in ArgoCD UI

## Best Practices

1. **Always use Git as source of truth**
   - Make changes in Git, not directly in cluster
   - Let ArgoCD sync changes automatically

2. **Test in lower environments first**
   - dev → test → qa → staging → prod

3. **Use meaningful commit messages**
   - Changes are tracked in Git history
   - Helps with troubleshooting and rollbacks

4. **Monitor sync status**
   - Set up alerts for sync failures
   - Review sync errors promptly

5. **Keep base and overlays organized**
   - Base contains common configuration
   - Overlays contain environment-specific changes

6. **Document environment-specific requirements**
   - Resource limits
   - External dependencies
   - Configuration differences

## Security Considerations

1. **Secrets Management**
   - Never commit secrets to Git
   - Use external secret management (Vault, Sealed Secrets)
   - Reference secrets in manifests, don't include values

2. **RBAC**
   - Limit who can modify ApplicationSets
   - Use ArgoCD projects for access control
   - Audit changes through Git history

3. **Image Security**
   - Use specific image tags, not `latest`
   - Scan images for vulnerabilities
   - Use private registries for production

## Support

For issues or questions:
- Review ArgoCD logs: `kubectl logs -n openshift-gitops -l app.kubernetes.io/name=argocd-application-controller`
- Check ApplicationSet status: `kubectl describe applicationset <name> -n openshift-gitops`
- Consult ArgoCD documentation: https://argo-cd.readthedocs.io/
- Contact the StreamSage platform team