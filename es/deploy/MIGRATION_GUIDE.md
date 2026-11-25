# Migration Guide: Ishanti Intelligence Collective (IIC) Deploy to StreamSage Deploy

**Date:** 2026-03-21  
**Purpose:** Consolidate IIC deployment patterns into StreamSage platform\
**Status:** Planning Document

---

## Executive Summary

This guide provides a comprehensive strategy for migrating the mature, production-ready deployment infrastructure from the **iic** repository into the **StreamSage** repository. The iic deploy directory represents a sophisticated GitOps implementation with ArgoCD ApplicationSets, multi-environment support, and enterprise-grade operational tooling that should be adopted by StreamSage.

### Key Findings

**IIC Deploy Strengths:**
- ✅ **Mature GitOps Architecture** - 7 ApplicationSets managing 55+ applications automatically
- ✅ **Comprehensive Documentation** - Extensive guides for operations, deployment, and troubleshooting
- ✅ **Multi-Environment Support** - 9 environments (dev, qa, test, staging, eem, ep, perf, prod, dr)
- ✅ **Enterprise Security** - NetworkPolicies, RBAC, SCC configurations
- ✅ **Operational Excellence** - Validation scripts, CI/CD pipelines, monitoring dashboards
- ✅ **Base/Overlay Pattern** - Consistent Kustomize structure across all components

**StreamSage Deploy Current State:**
- ⚠️ **Limited Structure** - Only 3 environments (test, prod, dr)
- ⚠️ **Manual Applications** - Individual ArgoCD Application files (not ApplicationSets)
- ⚠️ **Minimal Documentation** - Basic README only
- ⚠️ **No Validation Tools** - Missing pre-deployment validation scripts
- ⚠️ **Incomplete Coverage** - Missing monitoring, network policies, cluster config

---

## Comparison Matrix

| Feature | IIC Deploy | StreamSage Deploy | Action Required |
|---------|-------------|-------------------|-----------------|
| **GitOps Automation** | ApplicationSets (7) | Manual Apps (9) | ✅ Migrate ApplicationSets |
| **Environments** | 9 environments | 3 environments | ✅ Add 6 environments |
| **Base/Overlay Pattern** | Comprehensive | Basic | ✅ Enhance structure |
| **Documentation** | 11+ guides | 1 README | ✅ Port documentation |
| **Validation Scripts** | 5 scripts | None | ✅ Add validation |
| **CI/CD Pipelines** | Bitbucket + Tekton | None | ✅ Add pipelines |
| **Monitoring** | Grafana dashboards | None | ✅ Add monitoring |
| **Network Policies** | Complete | None | ✅ Add security |
| **Cluster Config** | Namespaces, RBAC, SCC | None | ✅ Add cluster mgmt |
| **ArgoCD Projects** | 3 projects with RBAC | 1 basic project | ✅ Enhance projects |

---

## Directory Structure Comparison

### IIC Deploy Structure (Source)

```
iic/deploy/
├── apps/
│   ├── argocd/
│   │   ├── applicationsets/          # 7 ApplicationSets (AUTO-GENERATION)
│   │   │   ├── cluster-config-appset.yaml
│   │   │   ├── event-streams-appset.yaml
│   │   │   ├── kafka-bridge-appset.yaml
│   │   │   ├── kafka-connect-appset.yaml
│   │   │   ├── kafka-topics-appset.yaml
│   │   │   ├── kafka-users-appset.yaml
│   │   │   ├── monitoring-appset.yaml
│   │   │   └── network-policies-appset.yaml
│   │   └── projects/                 # ArgoCD Projects with RBAC
│   │       ├── dev-project.yaml
│   │       ├── test-project.yaml
│   │       ├── prod-project.yaml
│   │       └── README.md (928 lines)
│   ├── base/                         # Base configurations
│   │   ├── event-streams/
│   │   ├── grafana/                  # Monitoring dashboards
│   │   ├── kafka-bridge/             # REST API
│   │   ├── kafka-connect/
│   │   ├── kafka-topics/
│   │   ├── kafka-users/
│   │   ├── mm2/                      # MirrorMaker2
│   │   ├── monitoring/
│   │   ├── network-policies/         # Zero-trust networking
│   │   ├── postgres/
│   │   ├── schema-registry/          # FHIR schemas
│   │   └── utility/
│   └── overlays/                     # 9 environments
│       ├── dev/
│       ├── dr/
│       ├── eem/
│       ├── ep/
│       ├── kafka/
│       ├── perf/
│       ├── qa/
│       ├── staging/
│       └── test/
├── clusters/
│   └── cluster-config/
│       ├── catalogs/                 # Operator catalogs
│       ├── namespaces/               # Base/overlay pattern
│       ├── operator/                 # Operator subscriptions
│       ├── rbac/
│       ├── scc/                      # Security Context Constraints
│       └── storage/
├── docs/                             # 11 comprehensive guides
│   ├── ARGOCD_GUIDE.md
│   ├── OPERATIONS_GUIDE.md
│   ├── CI_CD_PIPELINE_GUIDE.md
│   ├── DEPLOYMENT_GUIDE_NEW_CLUSTER.md
│   ├── DEPLOYMENT_CHECKLIST.md
│   ├── ENVIRONMENT_CONTROL_STRATEGY.md
│   ├── KAFKA_BRIDGE.md
│   ├── CRUISE_CONTROL.md
│   ├── NETWORK_POLICIES.md
│   ├── OPENSHIFT_SCC_TROUBLESHOOTING.md
│   └── MIRRORMAKER2.md
├── pipelines/                        # CI/CD automation
│   ├── scripts/
│   │   ├── build-kafka-connect.sh
│   │   ├── build-utility.sh
│   │   ├── security-scan.sh
│   │   └── update-kafkaconnect-cr.sh
│   ├── templates/
│   └── tekton/
└── scripts/                          # Validation & automation
    ├── validate-yaml.sh
    ├── validate-kustomize.sh
    ├── validate-resources.sh
    ├── validate-pre-deploy.sh
    ├── create-environment.sh
    ├── promote-environment.sh
    └── README.md (349 lines)
```

### StreamSage Deploy Structure (Target)

```
StreamSage/deploy/
├── apps/
│   ├── base/
│   │   ├── cruise-control/
│   │   ├── event-streams/
│   │   ├── kafka-connect/
│   │   ├── kafka-connectors/         # StreamSage-specific
│   │   ├── kafka-topics/             # StreamSage-specific
│   │   ├── monitoring/
│   │   ├── postgres/
│   │   ├── rbac/
│   │   ├── schema-registry/
│   │   └── streamsage-console/       # StreamSage-specific
│   └── overlays/
│       ├── dr/
│       ├── prod/
│       └── test/
├── argocd/
│   ├── applications/                 # Manual apps (to be replaced)
│   │   ├── dr/
│   │   ├── prod/
│   │   └── test/
│   └── projects/
│       └── event-streams.yaml
├── clusters/                         # Empty - needs content
├── scripts/                          # Empty - needs content
└── tests/                            # Empty - needs content
```

---

## Migration Strategy

### Phase 1: Foundation (Week 1)

**Objective:** Establish core infrastructure and GitOps automation

#### 1.1 ArgoCD ApplicationSets Migration

**Priority:** CRITICAL  
**Effort:** 2-3 days

**Actions:**
1. Create `StreamSage/deploy/apps/argocd/applicationsets/` directory
2. Migrate and adapt ApplicationSets:
   - `event-streams-appset.yaml` - Core Kafka clusters
   - `kafka-connect-appset.yaml` - Data integration
   - `kafka-topics-appset.yaml` - StreamSage topics
   - `monitoring-appset.yaml` - Grafana dashboards
   - `cluster-config-appset.yaml` - Cluster resources
3. Update repository URLs to StreamSage repo
4. Adjust path patterns for StreamSage structure
5. Test ApplicationSet generation

**Key Changes:**
```yaml
# IIC Pattern
repoURL: https://github.ibm.com/danutek/iic.git
path: deploy/apps/overlays/*/event-streams

# StreamSage Pattern
repoURL: https://github.ibm.com/danutek/StreamSage.git
path: deploy/apps/overlays/*/event-streams
```

**Benefits:**
- Automatic application generation for all environments
- 89% reduction in configuration files
- Consistent deployment patterns
- Automatic environment discovery

#### 1.2 Environment Expansion

**Priority:** HIGH  
**Effort:** 2 days

**Actions:**
1. Add missing environment overlays:
   - `dev/` - Development environment
   - `qa/` - Quality assurance
   - `staging/` - Pre-production
   - `eem/` - Event Endpoint Management
   - `ep/` - Event Processing
   - `perf/` - Performance testing
2. Create kustomization.yaml for each environment
3. Create environment-specific patches
4. Update namespace configurations

**Template Structure:**
```
overlays/{env}/
├── event-streams/
│   ├── kustomization.yaml
│   └── kafka-es-patch.yaml
├── kafka-connect/
│   ├── kustomization.yaml
│   └── kafka-connect-patch.yaml
├── kafka-topics/
│   ├── kustomization.yaml
│   └── topics.yaml
├── monitoring/
│   ├── kustomization.yaml
│   └── grafana-patch.yaml
└── streamsage-console/
    ├── kustomization.yaml
    └── console-patch.yaml
```

#### 1.3 Cluster Configuration

**Priority:** HIGH  
**Effort:** 1-2 days

**Actions:**
1. Create `StreamSage/deploy/clusters/cluster-config/` structure
2. Migrate namespace management (base/overlay pattern)
3. Add operator subscriptions
4. Configure storage classes
5. Set up RBAC policies
6. Configure Security Context Constraints (SCC)

**Components to Migrate:**
- `namespaces/` - Base/overlay namespace pattern
- `catalogs/` - IBM operator catalog
- `operator/` - PostgreSQL operator subscription
- `scc/` - Grafana SCC configurations
- `storage/` - Storage class definitions

---

### Phase 2: Security & Networking (Week 2)

**Objective:** Implement enterprise security controls

#### 2.1 Network Policies

**Priority:** HIGH  
**Effort:** 2 days

**Actions:**
1. Create `StreamSage/deploy/apps/base/network-policies/`
2. Migrate network policy definitions:
   - `default-deny-all.yaml` - Zero-trust baseline
   - `kafka-broker-netpol.yaml` - Kafka broker isolation
   - `kafka-connect-netpol.yaml` - Connect worker isolation
   - `postgres-netpol.yaml` - Database isolation
   - `streamsage-console-netpol.yaml` - Console access
3. Create NetworkPolicy ApplicationSet
4. Test network segmentation

**Benefits:**
- Zero-trust network architecture
- Microsegmentation between components
- Compliance with security standards
- Protection against lateral movement

#### 2.2 ArgoCD Projects Enhancement

**Priority:** MEDIUM  
**Effort:** 1 day

**Actions:**
1. Enhance `StreamSage/deploy/argocd/projects/`
2. Create environment-specific projects:
   - `dev-project.yaml` - Development with relaxed policies
   - `test-project.yaml` - Testing with moderate controls
   - `prod-project.yaml` - Production with strict controls
3. Configure RBAC policies per project
4. Set up sync windows for production
5. Configure resource whitelists/blacklists

**Key Features:**
- Environment isolation
- RBAC per environment
- Sync window controls
- Orphaned resource protection

---

### Phase 3: Operational Excellence (Week 3)

**Objective:** Add operational tooling and automation

#### 3.1 Validation Scripts

**Priority:** HIGH  
**Effort:** 1-2 days

**Actions:**
1. Create `StreamSage/deploy/scripts/` directory
2. Migrate validation scripts:
   - `validate-yaml.sh` - YAML syntax validation
   - `validate-kustomize.sh` - Kustomize build testing
   - `validate-resources.sh` - Resource configuration checks
   - `validate-pre-deploy.sh` - Comprehensive pre-deployment validation
3. Create StreamSage-specific scripts:
   - `validate-streamsage-topics.sh` - Topic configuration validation
   - `validate-connectors.sh` - Connector configuration validation
4. Add script documentation

**Benefits:**
- Catch configuration errors before deployment
- Automated validation in CI/CD
- Consistent quality checks
- Reduced deployment failures

#### 3.2 CI/CD Pipelines

**Priority:** MEDIUM  
**Effort:** 2-3 days

**Actions:**
1. Create `StreamSage/deploy/pipelines/` directory
2. Migrate pipeline components:
   - Build scripts for custom images
   - Security scanning with Trivy
   - Automated testing
3. Adapt for StreamSage services:
   - Python service builds (ingest-service, outbox-publisher, etc.)
   - Console builds (Next.js)
4. Configure Bitbucket Pipelines or GitHub Actions

**Pipeline Stages:**
1. Validation (YAML, Kustomize, Resources)
2. Build (Container images)
3. Security Scan (Trivy)
4. Push (Container registry)
5. Update GitOps (Update image tags)
6. Deploy (ArgoCD sync)

#### 3.3 Monitoring & Observability

**Priority:** HIGH  
**Effort:** 2 days

**Actions:**
1. Migrate Grafana dashboards from iic:
   - `kafka-overview-dashboard.json`
   - `kafka-topics-dashboard.json`
   - `consumer-groups-dashboard.json`
   - `kafka-connect-dashboard.json`
2. Create StreamSage-specific dashboards:
   - Transaction processing metrics
   - Service health dashboard
   - AI orchestration metrics
3. Configure Prometheus metrics collection
4. Set up alerting rules

---

### Phase 4: Documentation & Knowledge Transfer (Week 4)

**Objective:** Comprehensive documentation for StreamSage operations

#### 4.1 Documentation Migration

**Priority:** HIGH  
**Effort:** 3-4 days

**Actions:**
1. Create `StreamSage/deploy/docs/` directory
2. Migrate and adapt documentation:
   - `ARGOCD_GUIDE.md` - ApplicationSets and GitOps
   - `OPERATIONS_GUIDE.md` - Daily operations
   - `DEPLOYMENT_GUIDE.md` - New cluster deployment
   - `DEPLOYMENT_CHECKLIST.md` - Deployment tracking
   - `ENVIRONMENT_CONTROL_STRATEGY.md` - Environment management
3. Create StreamSage-specific guides:
   - `STREAMSAGE_SERVICES_GUIDE.md` - Service deployment
   - `TRANSACTION_PROCESSING_GUIDE.md` - Transaction workflows
   - `AI_ORCHESTRATION_GUIDE.md` - AI service operations
4. Update all references to StreamSage context

#### 4.2 Operational Runbooks

**Priority:** MEDIUM  
**Effort:** 2 days

**Actions:**
1. Create operational runbooks:
   - Incident response procedures
   - Scaling procedures
   - Backup and recovery
   - Disaster recovery
2. Document common troubleshooting scenarios
3. Create decision trees for operations

---

## Detailed Migration Steps

### Step 1: Backup Current State

```bash
# Backup StreamSage deploy directory
cd StreamSage
tar -czf deploy-backup-$(date +%Y%m%d).tar.gz deploy/

# Create migration branch
git checkout -b feature/deploy-migration
```

### Step 2: Create Directory Structure

```bash
# Create new directories
mkdir -p deploy/apps/argocd/applicationsets
mkdir -p deploy/clusters/cluster-config/{namespaces,catalogs,operator,rbac,scc,storage}
mkdir -p deploy/scripts
mkdir -p deploy/pipelines/{scripts,templates,tekton}
mkdir -p deploy/docs
mkdir -p deploy/apps/base/{network-policies,grafana,kafka-bridge,mm2,utility}

# Create environment overlays
for env in dev qa staging eem ep perf; do
  mkdir -p deploy/apps/overlays/$env/{event-streams,kafka-connect,kafka-topics,monitoring,streamsage-console}
done
```

### Step 3: Migrate ApplicationSets

```bash
# Copy ApplicationSets from iic
cp iic/deploy/apps/argocd/applicationsets/*.yaml \
   StreamSage/deploy/apps/argocd/applicationsets/

# Update repository URLs in all ApplicationSets
cd StreamSage/deploy/apps/argocd/applicationsets
sed -i 's|github.ibm.com/danutek/iic|github.ibm.com/danutek/StreamSage|g' *.yaml

# Validate ApplicationSets
for file in *.yaml; do
  echo "Validating $file..."
  oc kustomize --enable-alpha-plugins . || echo "Error in $file"
done
```

### Step 4: Migrate Base Configurations

```bash
# Copy base configurations (selective)
cp -r iic/deploy/apps/base/network-policies StreamSage/deploy/apps/base/
cp -r iic/deploy/apps/base/grafana StreamSage/deploy/apps/base/
cp -r iic/deploy/apps/base/monitoring StreamSage/deploy/apps/base/

# Update labels and references for StreamSage
find StreamSage/deploy/apps/base -name "*.yaml" -exec \
  sed -i 's/iic-kafka/streamsage/g' {} \;
```

### Step 5: Create Environment Overlays

```bash
# For each new environment
for env in dev qa staging eem ep perf; do
  # Event Streams overlay
  cat > StreamSage/deploy/apps/overlays/$env/event-streams/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: kafka-$env

bases:
  - ../../../base/event-streams

patchesStrategicMerge:
  - kafka-es-patch.yaml

commonLabels:
  environment: $env
  app.kubernetes.io/instance: kafka-$env
EOF

  # Create patch file template
  cat > StreamSage/deploy/apps/overlays/$env/event-streams/kafka-es-patch.yaml <<EOF
apiVersion: eventstreams.ibm.com/v1beta2
kind: EventStreams
metadata:
  name: kafka-es
spec:
  strimziOverrides:
    nodePools:
      - name: broker
        replicas: 3
        resources:
          requests:
            cpu: "1"
            memory: 4Gi
          limits:
            cpu: "2"
            memory: 8Gi
EOF
done
```

### Step 6: Migrate Cluster Configuration

```bash
# Copy cluster config
cp -r iic/deploy/clusters/cluster-config/* \
      StreamSage/deploy/clusters/cluster-config/

# Update namespace references
find StreamSage/deploy/clusters/cluster-config -name "*.yaml" -exec \
  sed -i 's/kafka-es-/kafka-/g' {} \;
```

### Step 7: Migrate Scripts

```bash
# Copy validation scripts
cp iic/scripts/*.sh StreamSage/deploy/scripts/
cp iic/scripts/README.md StreamSage/deploy/scripts/

# Make scripts executable
chmod +x StreamSage/deploy/scripts/*.sh

# Update script paths for StreamSage
cd StreamSage/deploy/scripts
sed -i 's|iic|StreamSage|g' *.sh
```

### Step 8: Migrate Documentation

```bash
# Copy documentation
cp iic/docs/*.md StreamSage/deploy/docs/

# Update references
cd StreamSage/deploy/docs
sed -i 's/IIC/StreamSage/g' *.md
sed -i 's/iic/StreamSage/g' *.md
sed -i 's/kafka-es-/kafka-/g' *.md
```

### Step 9: Validate Migration

```bash
# Run validation scripts
cd StreamSage/deploy
./scripts/validate-yaml.sh
./scripts/validate-kustomize.sh
./scripts/validate-resources.sh

# Test Kustomize builds for each environment
for env in test prod dr dev qa staging eem ep perf; do
  echo "Testing $env..."
  oc kustomize apps/overlays/$env/event-streams
done

# Validate ApplicationSets
oc apply --dry-run=client -f apps/argocd/applicationsets/
```

### Step 10: Deploy to Test Environment

```bash
# Apply cluster configuration first
oc apply -f deploy/apps/argocd/applicationsets/cluster-config-appset.yaml

# Wait for namespaces to be created
oc wait --for=condition=Ready namespace/kafka-test --timeout=60s

# Apply ApplicationSets
oc apply -f deploy/apps/argocd/applicationsets/event-streams-appset.yaml
oc apply -f deploy/apps/argocd/applicationsets/kafka-connect-appset.yaml
oc apply -f deploy/apps/argocd/applicationsets/monitoring-appset.yaml

# Monitor deployment
watch oc get applications -n openshift-gitops
```

---

## StreamSage-Specific Considerations

### 1. Service Deployments

StreamSage has multiple Python and Java services that need deployment configurations:

**Services to Add:**
- `ingest-service` - Python Kafka consumer
- `outbox-publisher` - Outbox pattern publisher
- `api-gateway` - FastAPI gateway
- `event-monitor` - Event monitoring service
- `quarkus-ingest` - Java ingest service
- `streamsage-console` - Next.js console (already exists)

**Action:** Create base and overlay configurations for each service following the iic pattern.

### 2. StreamSage Topics

StreamSage has specific topic requirements:

**Topics:**
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

**Action:** These already exist in `base/kafka-topics/` - ensure they're included in overlays.

### 3. Kafka Connectors

StreamSage uses JDBC sink connectors for PostgreSQL:

**Connectors:**
- Transaction connector
- Transaction family connector
- AI event connector
- Approval event connector
- Attachment event connector
- Audit event connector
- Notification event connector
- Workflow event connector

**Action:** These exist in `base/kafka-connectors/` - create overlay patches for environment-specific configuration.

### 4. PostgreSQL Integration

StreamSage requires PostgreSQL with specific schema:

**Action:**
- Migrate PostgreSQL operator configuration from iic
- Add StreamSage schema initialization
- Configure connection secrets per environment

---

## Risk Mitigation

### Risk 1: Breaking Existing Deployments

**Mitigation:**
- Perform migration in feature branch
- Test thoroughly in test environment
- Keep existing manual applications as backup
- Implement gradual rollout

### Risk 2: Configuration Drift

**Mitigation:**
- Use validation scripts before every deployment
- Implement CI/CD checks
- Regular audits of deployed vs. Git state
- ArgoCD auto-sync with prune enabled

### Risk 3: Documentation Gaps

**Mitigation:**
- Comprehensive documentation migration
- Create StreamSage-specific guides
- Regular documentation reviews
- Knowledge transfer sessions

### Risk 4: Service-Specific Issues

**Mitigation:**
- Test each service deployment independently
- Create service-specific runbooks
- Implement health checks and monitoring
- Gradual service rollout

---

## Testing Strategy

### Unit Testing

```bash
# Test individual Kustomize builds
oc kustomize deploy/apps/base/event-streams
oc kustomize deploy/apps/overlays/test/event-streams

# Test ApplicationSet generation (dry-run)
oc apply --dry-run=client -f deploy/apps/argocd/applicationsets/
```

### Integration Testing

```bash
# Deploy to test environment
oc apply -f deploy/apps/argocd/applicationsets/

# Verify applications created
oc get applications -n openshift-gitops

# Check application health
argocd app list
argocd app get test-event-streams
```

### End-to-End Testing

```bash
# Deploy full stack to test environment
./scripts/validate-pre-deploy.sh -e test
oc apply -k deploy/apps/overlays/test/

# Verify all components
oc get pods -n kafka-test
oc get eventstreams -n kafka-test
oc get kafkaconnect -n kafka-test

# Test service connectivity
oc exec -it deployment/ingest-service -n kafka-test -- curl http://api-gateway:8000/health
```

---

## Rollback Plan

### If Migration Fails

1. **Immediate Rollback:**
   ```bash
   # Switch back to main branch
   git checkout main
   
   # Reapply original configurations
   oc apply -f deploy/argocd/applications/
   ```

2. **Partial Rollback:**
   ```bash
   # Keep ApplicationSets but revert specific components
   oc delete -f deploy/apps/argocd/applicationsets/event-streams-appset.yaml
   oc apply -f deploy/argocd/applications/test/event-streams-app.yaml
   ```

3. **Data Preservation:**
   - PVCs are protected by orphaned resource policies
   - Secrets remain in namespaces
   - No data loss expected

---

## Success Criteria

### Phase 1 Success Metrics
- ✅ All 7 ApplicationSets deployed and generating applications
- ✅ All 9 environments have complete overlay structure
- ✅ Cluster configuration deployed successfully
- ✅ Test environment fully operational

### Phase 2 Success Metrics
- ✅ Network policies enforced across all environments
- ✅ ArgoCD projects configured with RBAC
- ✅ Zero security violations in test environment

### Phase 3 Success Metrics
- ✅ All validation scripts passing
- ✅ CI/CD pipeline operational
- ✅ Monitoring dashboards displaying metrics
- ✅ Automated deployments working

### Phase 4 Success Metrics
- ✅ Complete documentation available
- ✅ Team trained on new structure
- ✅ Operational runbooks validated
- ✅ Production deployment successful

---

## Timeline

| Phase | Duration | Dependencies | Deliverables |
|-------|----------|--------------|--------------|
| Phase 1: Foundation | Week 1 | None | ApplicationSets, Environments, Cluster Config |
| Phase 2: Security | Week 2 | Phase 1 | Network Policies, RBAC, Projects |
| Phase 3: Operations | Week 3 | Phase 1-2 | Scripts, Pipelines, Monitoring |
| Phase 4: Documentation | Week 4 | Phase 1-3 | Docs, Runbooks, Training |

**Total Duration:** 4 weeks  
**Buffer:** 1 week for issues and refinement  
**Target Completion:** 5 weeks from start

---

## Post-Migration Tasks

### Week 5: Stabilization

1. **Monitor Production:**
   - Watch for deployment issues
   - Review ArgoCD sync status
   - Check application health

2. **Performance Tuning:**
   - Optimize resource allocations
   - Adjust replica counts
   - Fine-tune monitoring

3. **Documentation Updates:**
   - Document any issues encountered
   - Update runbooks with real scenarios
   - Create FAQ based on team questions

### Ongoing Maintenance

1. **Regular Reviews:**
   - Monthly review of ApplicationSets
   - Quarterly documentation updates
   - Annual architecture review

2. **Continuous Improvement:**
   - Collect feedback from operations team
   - Implement automation improvements
   - Enhance monitoring and alerting

---

## Key Contacts

- **Migration Lead:** [Name]
- **Platform Engineering:** [Team]
- **ArgoCD Admin:** [Name]
- **Security Review:** [Team]
- **Documentation:** [Name]

---

## References

### IIC Documentation
- [`iic/README.md`](../iic/README.md) - Main repository overview
- [`iic/deploy/apps/argocd/applicationsets/README.md`](../iic/deploy/apps/argocd/applicationsets/README.md) - ApplicationSets guide
- [`iic/deploy/apps/argocd/projects/README.md`](../iic/deploy/apps/argocd/projects/README.md) - Projects guide
- [`iic/docs/ARGOCD_GUIDE.md`](../iic/docs/ARGOCD_GUIDE.md) - ArgoCD operations
- [`iic/docs/OPERATIONS_GUIDE.md`](../iic/docs/OPERATIONS_GUIDE.md) - Daily operations
- [`iic/scripts/README.md`](../iic/scripts/README.md) - Validation scripts

### StreamSage Documentation
- [`StreamSage/README.md`](../README.md) - Platform overview
- [`StreamSage/platform_principles.md`](../platform_principles.md) - Design principles

### External Resources
- [ArgoCD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Kustomize Documentation](https://kustomize.io/)
- [OpenShift GitOps](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)

---

## Appendix A: File Mapping

| IIC File | StreamSage Target | Notes |
|-----------|-------------------|-------|
| `deploy/apps/argocd/applicationsets/*.yaml` | `deploy/apps/argocd/applicationsets/*.yaml` | Update repo URLs |
| `deploy/apps/base/event-streams/*` | `deploy/apps/base/event-streams/*` | Merge with existing |
| `deploy/apps/base/kafka-connect/*` | `deploy/apps/base/kafka-connect/*` | Merge with existing |
| `deploy/apps/base/network-policies/*` | `deploy/apps/base/network-policies/*` | New directory |
| `deploy/apps/base/grafana/*` | `deploy/apps/base/grafana/*` | New directory |
| `deploy/clusters/cluster-config/*` | `deploy/clusters/cluster-config/*` | New structure |
| `scripts/*.sh` | `deploy/scripts/*.sh` | Update paths |
| `docs/*.md` | `deploy/docs/*.md` | Update references |

---

## Appendix B: Environment Configuration Matrix

| Environment | Brokers | Controllers | Storage | CPU | Memory | Purpose |
|-------------|---------|-------------|---------|-----|--------|---------|
| dev | 3 | 3 | 50Gi | 1 | 4Gi | Development |
| qa | 3 | 3 | 100Gi | 1 | 8Gi | QA Testing |
| test | 3 | 3 | 100Gi | 1 | 8Gi | Integration Testing |
| staging | 5 | 3 | 250Gi | 2 | 12Gi | Pre-production |
| eem | 3 | 3 | 100Gi | 1 | 8Gi | Event Endpoint Mgmt |
| ep | 3 | 3 | 100Gi | 1 | 8Gi | Event Processing |
| perf | 5 | 3 | 250Gi | 2 | 12Gi | Performance Testing |
| prod | 5 | 3 | 500Gi | 2 | 12Gi | Production |
| dr | 5 | 3 | 500Gi | 2 | 12Gi | Disaster Recovery |

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-21  
**Next Review:** After Phase 1 completion
