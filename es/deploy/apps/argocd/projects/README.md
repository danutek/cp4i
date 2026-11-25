# StreamSage ArgoCD Projects

This directory contains ArgoCD AppProject definitions for managing StreamSage deployments across all environments with proper RBAC and sync policies.

## Overview

ArgoCD Projects provide a logical grouping of applications with:
- **Source repository restrictions** - Which Git repos can be used
- **Destination restrictions** - Which clusters/namespaces can be deployed to
- **Resource restrictions** - Which Kubernetes resources can be managed
- **RBAC policies** - Who can access and manage applications
- **Sync windows** - When deployments are allowed

## Project Structure

### Two Bundles per Environment

Each environment has **two separate projects**:

1. **StreamSage Project** (`streamsage-{env}-project.yaml`)
   - Manages application services (console, backend services)
   - Deploys to: `streamsage-{env}`, `postgres-{env}` namespaces
   - Resources: Deployments, Services, Routes, ConfigMaps, Secrets

2. **EventStreams Project** (`eventstreams-{env}-project.yaml`)
   - Manages Kafka/Event Streams infrastructure
   - Deploys to: `kafka-{env}` namespace
   - Resources: EventStreams, KafkaConnect, KafkaTopics, etc.

### Total Projects: 18

- 9 environments × 2 bundles = 18 projects

## Environments

| Environment | Code | Purpose | Sync Schedule |
|-------------|------|---------|---------------|
| Development | dev | Rapid development | Always (24/7) |
| Test | test | Automated testing | Always (24/7) |
| QA | qa | Quality assurance | Business hours (6am-6pm Mon-Fri) |
| Staging | staging | Pre-production | Business hours (8am-5pm Mon-Fri) |
| Performance | perf | Load testing | Extended hours (6am-10pm daily) |
| Production | prod | Live production | Maintenance windows (2-4am Sun/Wed) |
| Enterprise Prod | ep | High-scale production | Maintenance windows (2-4am Sun only) |
| Enterprise EM | eem | Event management | Business hours (6am-6pm Mon-Fri) |
| Disaster Recovery | dr | Business continuity | Maintenance windows (2-4am Sun/Wed) |

## Sync Windows

Sync windows control when automated deployments can occur:

### Development Environments (dev, test)
```yaml
schedule: '* * * * *'  # Always allowed
```
- 24/7 deployment capability
- Supports rapid iteration
- Allows all source repositories

### QA/Staging/EEM Environments
```yaml
schedule: '0 6-18 * * 1-5'  # Business hours, weekdays
```
- Monday-Friday, 6am-6pm
- Prevents after-hours disruptions
- Controlled deployment windows

### Performance Environment
```yaml
schedule: '0 6-22 * * *'  # Extended hours, daily
```
- Daily, 6am-10pm
- Supports extended testing schedules
- Flexible deployment timing

### Production Environments (prod, dr)
```yaml
schedule: '0 2-4 * * 0,3'  # Maintenance windows
```
- Sunday and Wednesday, 2-4am
- Minimal business impact
- Coordinated deployment windows

### Enterprise Production (ep)
```yaml
schedule: '0 2-4 * * 0'  # Weekly maintenance
```
- Sunday only, 2-4am
- Most restrictive schedule
- Maximum stability

## RBAC Roles

Each project defines two roles:

### Admin Role (`{env}-admin`)
**Permissions:**
- Full application management
- Sync applications
- Override sync policies
- Execute application actions

**Groups:**
- `streamsage-{env}-admins` or `eventstreams-{env}-admins`
- `platform-engineers`

### Viewer Role (`{env}-viewer`)
**Permissions:**
- Read-only access
- View application status
- View sync history

**Groups:**
- `streamsage-viewers` or `eventstreams-viewers`
- `all-engineers`

## Resource Permissions

### StreamSage Projects

**Cluster-scoped resources:**
- Namespaces (creation only)

**Namespace-scoped resources:**
- Deployments, StatefulSets, DaemonSets
- Services, Endpoints
- ConfigMaps, Secrets
- Routes (OpenShift)
- NetworkPolicies
- PersistentVolumeClaims

### EventStreams Projects

**Cluster-scoped resources:**
- Namespaces (creation only)
- EventStreams CRDs (`eventstreams.ibm.com`)
- Kafka CRDs (`kafka.strimzi.io`)

**Namespace-scoped resources:**
- All resources (`*/*`)
- Full Kafka/Strimzi resource management

## Orphaned Resources

Resources preserved when applications are deleted:

### StreamSage Projects
- PersistentVolumeClaims (data preservation)
- Secrets (security)

### EventStreams Projects
- PersistentVolumeClaims (Kafka data)
- Secrets (certificates, credentials)
- KafkaUsers (user management)
- KafkaTopics (topic preservation)

## Usage

### Applying Projects

```bash
# Apply all projects
kubectl apply -f deploy/apps/argocd/projects/

# Apply specific bundle
kubectl apply -f deploy/apps/argocd/projects/streamsage-*-project.yaml
kubectl apply -f deploy/apps/argocd/projects/eventstreams-*-project.yaml

# Apply specific environment
kubectl apply -f deploy/apps/argocd/projects/streamsage-dev-project.yaml
kubectl apply -f deploy/apps/argocd/projects/eventstreams-dev-project.yaml
```

### Verifying Projects

```bash
# List all projects
kubectl get appprojects -n openshift-gitops

# Get project details
kubectl describe appproject streamsage-dev -n openshift-gitops

# View project in ArgoCD UI
argocd proj list
argocd proj get streamsage-dev
```

### Checking RBAC

```bash
# View project roles
argocd proj role list streamsage-dev

# View role policies
argocd proj role get streamsage-dev dev-admin
```

## Project Files

### StreamSage Projects (9 files)
```
streamsage-dev-project.yaml       # Development
streamsage-test-project.yaml      # Testing
streamsage-qa-project.yaml        # QA
streamsage-staging-project.yaml   # Staging
streamsage-perf-project.yaml      # Performance
streamsage-prod-project.yaml      # Production
streamsage-ep-project.yaml        # Enterprise Production
streamsage-eem-project.yaml       # Enterprise Event Management
streamsage-dr-project.yaml        # Disaster Recovery
```

### EventStreams Projects (9 files)
```
eventstreams-dev-project.yaml       # Development
eventstreams-test-project.yaml      # Testing
eventstreams-qa-project.yaml        # QA
eventstreams-staging-project.yaml   # Staging
eventstreams-perf-project.yaml      # Performance
eventstreams-prod-project.yaml      # Production
eventstreams-ep-project.yaml        # Enterprise Production
eventstreams-eem-project.yaml       # Enterprise Event Management
eventstreams-dr-project.yaml        # Disaster Recovery
```

## Security Best Practices

1. **Least Privilege**
   - Projects restrict access to specific namespaces
   - RBAC roles limit permissions appropriately
   - Production has most restrictive policies

2. **Source Control**
   - Only approved Git repositories allowed
   - Development allows flexibility with `*`
   - Production restricts to official repo only

3. **Sync Windows**
   - Production deployments during maintenance windows
   - Prevents unauthorized changes during business hours
   - Coordinated deployment schedules

4. **Resource Protection**
   - Orphaned resources prevent data loss
   - PVCs preserved on application deletion
   - Secrets maintained for security

5. **Audit Trail**
   - All changes tracked in Git
   - ArgoCD maintains sync history
   - RBAC policies logged

## Troubleshooting

### Application Can't Deploy

**Check project permissions:**
```bash
kubectl describe appproject streamsage-dev -n openshift-gitops
```

**Verify namespace is allowed:**
```yaml
destinations:
  - namespace: 'streamsage-dev'
    server: 'https://kubernetes.default.svc'
```

### Sync Window Blocked

**Check current sync windows:**
```bash
argocd proj get streamsage-prod
```

**Manually sync during window:**
```bash
argocd app sync my-app --force
```

### RBAC Denied

**Check user groups:**
```bash
argocd account get-user-info
```

**Verify role membership:**
```bash
argocd proj role get streamsage-dev dev-admin
```

### Resource Not Allowed

**Check resource whitelists:**
```bash
kubectl get appproject streamsage-dev -n openshift-gitops -o yaml
```

**Add resource to whitelist if needed:**
```yaml
namespaceResourceWhitelist:
  - group: 'custom.io'
    kind: 'CustomResource'
```

## Maintenance

### Adding New Environment

1. Create both project files:
   ```bash
   cp streamsage-dev-project.yaml streamsage-newenv-project.yaml
   cp eventstreams-dev-project.yaml eventstreams-newenv-project.yaml
   ```

2. Update environment references:
   - Project name
   - Namespace destinations
   - Labels
   - RBAC group names

3. Set appropriate sync schedule

4. Apply projects:
   ```bash
   kubectl apply -f streamsage-newenv-project.yaml
   kubectl apply -f eventstreams-newenv-project.yaml
   ```

### Modifying Sync Windows

Edit project file and update schedule:
```yaml
syncWindows:
  - kind: allow
    schedule: '0 2-4 * * 0,3'  # Cron format
```

Apply changes:
```bash
kubectl apply -f streamsage-prod-project.yaml
```

### Adding RBAC Groups

Add group to role:
```yaml
roles:
  - name: dev-admin
    groups:
      - new-group-name
```

Apply changes:
```bash
kubectl apply -f streamsage-dev-project.yaml
```

## Integration with ApplicationSets

Projects are referenced by ApplicationSets:

```yaml
# In ApplicationSet
spec:
  template:
    spec:
      project: streamsage-dev  # References project name
```

**Relationship:**
- ApplicationSets generate Applications
- Applications must belong to a Project
- Projects enforce policies on Applications

## Monitoring

### Project Health

```bash
# Check all projects
kubectl get appprojects -n openshift-gitops

# Check specific project
kubectl get appproject streamsage-dev -n openshift-gitops -o yaml
```

### Application Compliance

```bash
# List applications in project
argocd app list --project streamsage-dev

# Check application project assignment
argocd app get my-app -o yaml | grep project
```

### Sync Window Status

```bash
# Check if sync is allowed now
argocd proj windows list streamsage-prod

# View upcoming windows
argocd proj windows list streamsage-prod --upcoming
```

## Support

For issues or questions:
- Review project YAML for configuration
- Check ArgoCD logs: `kubectl logs -n openshift-gitops -l app.kubernetes.io/name=argocd-application-controller`
- Verify RBAC with: `argocd account can-i sync applications '*'`
- Contact platform engineering team