# ArgoCD Projects Summary

## Overview

Created 18 ArgoCD AppProject definitions for managing StreamSage deployments with proper RBAC, resource restrictions, and sync policies.

## Project Structure

### Two Bundles per Environment

Each of the 9 environments has 2 separate projects:

1. **StreamSage Bundle** - Application services
2. **EventStreams Bundle** - Kafka infrastructure

**Total**: 9 environments × 2 bundles = **18 projects**

## Created Projects

### StreamSage Projects (9)

| Project | Environment | Namespaces | Sync Schedule |
|---------|-------------|------------|---------------|
| streamsage-dev | Development | streamsage-dev, postgres-dev | Always (24/7) |
| streamsage-test | Testing | streamsage-test, postgres-test | Always (24/7) |
| streamsage-qa | QA | streamsage-qa, postgres-qa | 6am-6pm Mon-Fri |
| streamsage-staging | Staging | streamsage-staging, postgres-staging | 8am-5pm Mon-Fri |
| streamsage-perf | Performance | streamsage-perf, postgres-perf | 6am-10pm Daily |
| streamsage-prod | Production | streamsage-prod, postgres-prod | 2-4am Sun/Wed |
| streamsage-ep | Enterprise Prod | streamsage-ep, postgres-ep | 2-4am Sun only |
| streamsage-eem | Enterprise EM | streamsage-eem, postgres-eem | 6am-6pm Mon-Fri |
| streamsage-dr | Disaster Recovery | streamsage-dr, postgres-dr | 2-4am Sun/Wed |

### EventStreams Projects (9)

| Project | Environment | Namespaces | Sync Schedule |
|---------|-------------|------------|---------------|
| eventstreams-dev | Development | kafka-dev | Always (24/7) |
| eventstreams-test | Testing | kafka-test | Always (24/7) |
| eventstreams-qa | QA | kafka-qa | 6am-6pm Mon-Fri |
| eventstreams-staging | Staging | kafka-staging | 8am-5pm Mon-Fri |
| eventstreams-perf | Performance | kafka-perf | 6am-10pm Daily |
| eventstreams-prod | Production | kafka-prod | 2-4am Sun/Wed |
| eventstreams-ep | Enterprise Prod | kafka-ep | 2-4am Sun only |
| eventstreams-eem | Enterprise EM | kafka-eem | 6am-6pm Mon-Fri |
| eventstreams-dr | Disaster Recovery | kafka-dr | 2-4am Sun/Wed |

## Key Features

### 1. Environment Isolation
- Each environment has dedicated namespaces
- Separate projects prevent cross-environment deployments
- Clear separation between application and infrastructure

### 2. RBAC Policies
Each project defines two roles:
- **Admin Role**: Full management capabilities
  - Groups: `{bundle}-{env}-admins`, `platform-engineers`
- **Viewer Role**: Read-only access
  - Groups: `{bundle}-viewers`, `all-engineers`

### 3. Sync Windows
Deployment timing controlled by environment:
- **Dev/Test**: 24/7 (rapid iteration)
- **QA/Staging/EEM**: Business hours (controlled testing)
- **Perf**: Extended hours (flexible testing)
- **Prod/DR**: Maintenance windows (minimal impact)
- **EP**: Weekly maintenance (maximum stability)

### 4. Resource Restrictions

**StreamSage Projects:**
- Deployments, Services, Routes
- ConfigMaps, Secrets
- NetworkPolicies
- PersistentVolumeClaims

**EventStreams Projects:**
- EventStreams CRDs
- Kafka/Strimzi CRDs
- All Kafka-related resources

### 5. Orphaned Resource Protection
Resources preserved on application deletion:
- PersistentVolumeClaims (data)
- Secrets (credentials)
- KafkaUsers (user management)
- KafkaTopics (topic preservation)

## Sync Schedule Details

### Cron Format Explanation

| Schedule | Meaning | Environments |
|----------|---------|--------------|
| `* * * * *` | Every minute (always) | dev, test |
| `0 6-18 * * 1-5` | Hourly 6am-6pm Mon-Fri | qa, eem |
| `0 8-17 * * 1-5` | Hourly 8am-5pm Mon-Fri | staging |
| `0 6-22 * * *` | Hourly 6am-10pm Daily | perf |
| `0 2-4 * * 0,3` | Hourly 2-4am Sun/Wed | prod, dr |
| `0 2-4 * * 0` | Hourly 2-4am Sun only | ep |

## Deployment Flow

```
1. Apply Projects
   ↓
2. Projects enforce policies
   ↓
3. ApplicationSets reference projects
   ↓
4. Applications created within project scope
   ↓
5. Sync windows control deployment timing
   ↓
6. RBAC controls who can manage
```

## Usage

### Apply All Projects
```bash
kubectl apply -f deploy/apps/argocd/projects/
```

### Apply by Bundle
```bash
# StreamSage projects only
kubectl apply -f deploy/apps/argocd/projects/streamsage-*-project.yaml

# EventStreams projects only
kubectl apply -f deploy/apps/argocd/projects/eventstreams-*-project.yaml
```

### Apply by Environment
```bash
# Development projects
kubectl apply -f deploy/apps/argocd/projects/*-dev-project.yaml

# Production projects
kubectl apply -f deploy/apps/argocd/projects/*-prod-project.yaml
```

### Verify Projects
```bash
# List all projects
kubectl get appprojects -n openshift-gitops

# Should show 18 projects
kubectl get appprojects -n openshift-gitops | wc -l
```

## Integration Points

### With ApplicationSets
ApplicationSets reference projects:
```yaml
spec:
  template:
    spec:
      project: streamsage-dev  # Must match project name
```

### With Applications
Applications inherit project policies:
- Source repository restrictions
- Destination namespace restrictions
- Resource type restrictions
- RBAC policies
- Sync windows

## Security Model

### Principle of Least Privilege
1. **Development**: Flexible (allows all repos, 24/7 sync)
2. **QA/Staging**: Controlled (business hours, restricted repos)
3. **Production**: Restricted (maintenance windows, official repo only)

### Defense in Depth
- Project-level restrictions
- RBAC role-based access
- Sync window timing controls
- Resource type whitelisting
- Namespace isolation

## Monitoring

### Health Checks
```bash
# Check all projects
kubectl get appprojects -n openshift-gitops

# Check specific project
kubectl describe appproject streamsage-dev -n openshift-gitops
```

### Application Compliance
```bash
# List apps in project
argocd app list --project streamsage-dev

# Verify project assignment
argocd app get my-app | grep project
```

### Sync Window Status
```bash
# Check if sync allowed now
argocd proj windows list streamsage-prod

# View upcoming windows
argocd proj windows list streamsage-prod --upcoming
```

## File Organization

```
deploy/apps/argocd/projects/
├── README.md                          # Comprehensive documentation
├── PROJECTS_SUMMARY.md               # This file
├── eventstreams-dev-project.yaml     # EventStreams dev
├── eventstreams-test-project.yaml    # EventStreams test
├── eventstreams-qa-project.yaml      # EventStreams qa
├── eventstreams-staging-project.yaml # EventStreams staging
├── eventstreams-perf-project.yaml    # EventStreams perf
├── eventstreams-prod-project.yaml    # EventStreams prod
├── eventstreams-ep-project.yaml      # EventStreams ep
├── eventstreams-eem-project.yaml     # EventStreams eem
├── eventstreams-dr-project.yaml      # EventStreams dr
├── streamsage-dev-project.yaml       # StreamSage dev
├── streamsage-test-project.yaml      # StreamSage test
├── streamsage-qa-project.yaml        # StreamSage qa
├── streamsage-staging-project.yaml   # StreamSage staging
├── streamsage-perf-project.yaml      # StreamSage perf
├── streamsage-prod-project.yaml      # StreamSage prod
├── streamsage-ep-project.yaml        # StreamSage ep
├── streamsage-eem-project.yaml       # StreamSage eem
└── streamsage-dr-project.yaml        # StreamSage dr
```

## Benefits

### 1. Separation of Concerns
- Application services separate from infrastructure
- Clear ownership boundaries
- Independent lifecycle management

### 2. Environment Progression
- Controlled promotion path: dev → test → qa → staging → prod
- Different policies per environment
- Risk mitigation through staged rollout

### 3. Security & Compliance
- RBAC enforcement
- Audit trail through Git
- Sync window compliance
- Resource restrictions

### 4. Operational Excellence
- Automated policy enforcement
- Consistent deployment patterns
- Reduced human error
- Clear access controls

## Next Steps

1. **Apply Projects**
   ```bash
   kubectl apply -f deploy/apps/argocd/projects/
   ```

2. **Configure RBAC Groups**
   - Set up AD/LDAP groups
   - Map to ArgoCD roles
   - Test access controls

3. **Update ApplicationSets**
   - Ensure correct project references
   - Verify namespace alignment
   - Test application generation

4. **Monitor Deployments**
   - Set up alerts for sync failures
   - Monitor sync window compliance
   - Track RBAC violations

5. **Document Procedures**
   - Emergency deployment process
   - Sync window override procedures
   - RBAC escalation path

## Support

For questions or issues:
- Review [README.md](README.md) for detailed documentation
- Check project YAML for specific configuration
- Verify RBAC with: `argocd account can-i sync applications '*'`
- Contact platform engineering team

## Success Criteria

✅ 18 projects created (9 environments × 2 bundles)
✅ RBAC roles defined for each project
✅ Sync windows configured appropriately
✅ Resource restrictions in place
✅ Orphaned resource protection enabled
✅ Documentation completed
✅ Ready for deployment