# StreamSage Deployment Runbook

**Version:** 1.0  
**Last Updated:** 2026-03-21  
**Owner:** Platform Team

---

## Overview

This runbook provides step-by-step procedures for deploying StreamSage components to OpenShift clusters using ArgoCD and GitOps practices.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Cluster Setup](#initial-cluster-setup)
3. [Deploy to Development](#deploy-to-development)
4. [Deploy to Test](#deploy-to-test)
5. [Deploy to Staging](#deploy-to-staging)
6. [Deploy to Production](#deploy-to-production)
7. [Rollback Procedures](#rollback-procedures)
8. [Verification Steps](#verification-steps)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Access
- [ ] OpenShift cluster admin access
- [ ] ArgoCD admin access
- [ ] Git repository write access
- [ ] Quay.io registry access

### Required Tools
```bash
# Verify tools are installed
oc version                    # OpenShift CLI
argocd version               # ArgoCD CLI
kubectl version              # Kubernetes CLI
git --version                # Git
```

### Required Credentials
- [ ] OpenShift login token
- [ ] ArgoCD admin password
- [ ] Quay.io credentials
- [ ] Database credentials (stored in secrets)

---

## Initial Cluster Setup

### Step 1: Login to OpenShift

```bash
# Login to OpenShift cluster
oc login https://api.cluster.example.com:6443 --token=<your-token>

# Verify cluster access
oc whoami
oc get nodes
```

### Step 2: Create Namespaces

```bash
# Apply cluster configuration
oc apply -k deploy/clusters/cluster-config/namespaces/overlays/dev/

# Verify namespaces created
oc get namespaces | grep -E "kafka-dev|streamsage-dev"
```

**Expected Output:**
```
kafka-dev          Active   1m
streamsage-dev     Active   1m
```

### Step 3: Install Operators

```bash
# Install IBM Event Streams operator
oc apply -f deploy/clusters/cluster-config/operator/event-streams-subscription.yaml

# Install PostgreSQL operator (if needed)
oc apply -f deploy/clusters/cluster-config/operator/postgres-subscription.yaml

# Verify operators installed
oc get csv -n openshift-operators
```

**Wait for operators to be in "Succeeded" phase before proceeding.**

### Step 4: Setup ArgoCD

```bash
# Login to ArgoCD
argocd login argocd.apps.cluster.example.com --username admin --password <password>

# Create ArgoCD projects
oc apply -f deploy/apps/argocd/projects/streamsage-dev-project.yaml
oc apply -f deploy/apps/argocd/projects/streamsage-prod-project.yaml

# Verify projects created
argocd proj list
```

### Step 5: Deploy ApplicationSets

```bash
# Apply all ApplicationSets
oc apply -f deploy/apps/argocd/applicationsets/

# Verify ApplicationSets created
oc get applicationsets -n openshift-gitops

# Check generated applications
oc get applications -n openshift-gitops
```

---

## Deploy to Development

### Pre-Deployment Checklist
- [ ] All validation scripts pass
- [ ] Code reviewed and approved
- [ ] Changes merged to main branch
- [ ] CI/CD pipeline completed successfully

### Step 1: Verify Configuration

```bash
# Validate YAML syntax
./deploy/scripts/validate-yaml.sh

# Validate Kustomize builds
./deploy/scripts/validate-kustomize.sh

# Validate resources
./deploy/scripts/validate-resources.sh
```

### Step 2: Deploy Event Streams (Kafka)

```bash
# Sync Event Streams application
argocd app sync dev-event-streams --prune

# Wait for sync to complete
argocd app wait dev-event-streams --health --timeout 600

# Verify Kafka cluster is ready
oc get eventstreams -n kafka-dev
oc get pods -n kafka-dev
```

**Expected State:**
- EventStreams CR: Ready
- Kafka pods: 3/3 Running
- ZooKeeper pods: 3/3 Running

### Step 3: Deploy Kafka Connect

```bash
# Sync Kafka Connect application
argocd app sync dev-kafka-connect --prune

# Wait for sync to complete
argocd app wait dev-kafka-connect --health --timeout 300

# Verify Kafka Connect is ready
oc get kafkaconnect -n kafka-dev
oc get pods -n kafka-dev | grep connect
```

**Expected State:**
- KafkaConnect CR: Ready
- Connect pods: 2/2 Running

### Step 4: Deploy Kafka Topics

```bash
# Sync Kafka Topics application
argocd app sync dev-kafka-topics --prune

# Wait for sync to complete
argocd app wait dev-kafka-topics --health --timeout 180

# Verify topics created
oc get kafkatopics -n kafka-dev
```

**Expected Topics:**
- streamsage.ingest.transaction
- streamsage.transaction.event
- streamsage.ai.event
- (and others)

### Step 5: Deploy Network Policies

```bash
# Sync Network Policies application
argocd app sync dev-network-policies --prune

# Verify network policies applied
oc get networkpolicies -n kafka-dev
oc get networkpolicies -n streamsage-dev
```

### Step 6: Deploy StreamSage Services

```bash
# Deploy services (if using separate applications)
argocd app sync dev-streamsage-services --prune

# Verify services are running
oc get pods -n streamsage-dev
oc get svc -n streamsage-dev
```

### Step 7: Deploy StreamSage Console

```bash
# Sync Console application
argocd app sync dev-streamsage-console --prune

# Wait for deployment
argocd app wait dev-streamsage-console --health --timeout 300

# Verify console is accessible
oc get route -n streamsage-dev
```

### Step 8: Verification

```bash
# Check all applications are synced and healthy
argocd app list | grep dev-

# Verify all pods are running
oc get pods -n kafka-dev
oc get pods -n streamsage-dev

# Test connectivity
oc exec -n kafka-dev deployment/kafka-connect -- curl -s http://localhost:8083/
```

---

## Deploy to Test

### Prerequisites
- [ ] Development deployment successful
- [ ] Integration tests passed
- [ ] Manual testing completed in dev

### Step 1: Promote Images

```bash
# Trigger promotion via GitHub Actions
# Method 1: Commit message
git commit -m "feat: promote to test [promote-test]"
git push origin main

# Method 2: Manual workflow dispatch
# Go to GitHub Actions → Build and Deploy → Run workflow → Select "test"
```

### Step 2: Sync Applications

```bash
# Sync all test applications
argocd app sync test-event-streams test-kafka-connect test-kafka-topics test-network-policies test-streamsage-console --prune

# Wait for all to be healthy
argocd app wait test-event-streams test-kafka-connect test-kafka-topics test-network-policies test-streamsage-console --health --timeout 600
```

### Step 3: Verification

```bash
# Check application status
argocd app list | grep test-

# Verify pods are running
oc get pods -n kafka-test
oc get pods -n streamsage-test

# Run smoke tests
./deploy/scripts/test-connectivity.sh test
```

---

## Deploy to Staging

### Prerequisites
- [ ] Test deployment successful
- [ ] End-to-end tests passed
- [ ] Performance tests completed
- [ ] Security scan passed

### Step 1: Promote to Staging

```bash
# Promote via commit message
git commit -m "feat: promote to staging [promote-staging]"
git push origin main
```

### Step 2: Sync Applications

```bash
# Sync staging applications
argocd app sync staging-event-streams staging-kafka-connect staging-kafka-topics staging-network-policies staging-streamsage-console --prune

# Monitor deployment
watch argocd app list | grep staging-
```

### Step 3: Verification

```bash
# Comprehensive verification
./deploy/scripts/verify-deployment.sh staging

# Check monitoring
oc get pods -n openshift-monitoring
curl -s http://prometheus.apps.cluster.example.com/api/v1/query?query=up{job="kafka-broker"}
```

---

## Deploy to Production

### Prerequisites
- [ ] Staging deployment successful
- [ ] Load testing completed
- [ ] Security review approved
- [ ] Change management approval
- [ ] Maintenance window scheduled

### Step 1: Pre-Production Checklist

```bash
# Verify production readiness
./deploy/scripts/production-readiness-check.sh

# Backup current state
./deploy/scripts/backup-production.sh

# Verify rollback plan
./deploy/scripts/verify-rollback-plan.sh
```

### Step 2: Production Deployment

```bash
# Promote to production (requires approval)
git commit -m "feat: promote to production [promote-prod]"
git push origin main

# Monitor GitHub Actions for approval gate
# Approve deployment in GitHub UI
```

### Step 3: Sync Applications (Manual)

```bash
# Production sync requires manual approval
argocd app sync prod-event-streams --prune
# Wait and verify before proceeding

argocd app sync prod-kafka-connect --prune
# Wait and verify before proceeding

argocd app sync prod-kafka-topics --prune
# Wait and verify before proceeding

argocd app sync prod-network-policies --prune
# Wait and verify before proceeding

argocd app sync prod-streamsage-console --prune
# Final verification
```

### Step 4: Post-Deployment Verification

```bash
# Comprehensive production verification
./deploy/scripts/production-verification.sh

# Monitor for 30 minutes
watch -n 30 'oc get pods -n kafka-prod && oc get pods -n streamsage-prod'

# Check monitoring dashboards
# - Grafana: https://grafana.apps.cluster.example.com
# - Prometheus: https://prometheus.apps.cluster.example.com
```

---

## Rollback Procedures

### Emergency Rollback

**When to use:** Critical production issues, data corruption, security breach

```bash
# 1. Immediate rollback via ArgoCD
argocd app rollback prod-streamsage-console <previous-revision>
argocd app rollback prod-kafka-connect <previous-revision>

# 2. Verify rollback
argocd app get prod-streamsage-console
argocd app get prod-kafka-connect

# 3. Monitor system recovery
watch oc get pods -n streamsage-prod
```

### Planned Rollback

**When to use:** Planned maintenance, version downgrade

```bash
# 1. Update Git to previous version
git revert <commit-hash>
git push origin main

# 2. Sync applications
argocd app sync prod-streamsage-console --prune
argocd app sync prod-kafka-connect --prune

# 3. Verify rollback complete
./deploy/scripts/verify-deployment.sh prod
```

### Database Rollback

**When to use:** Schema changes, data migration issues

```bash
# 1. Stop applications
oc scale deployment streamsage-services --replicas=0 -n streamsage-prod

# 2. Restore database
./deploy/scripts/restore-database.sh <backup-timestamp>

# 3. Restart applications
oc scale deployment streamsage-services --replicas=3 -n streamsage-prod
```

---

## Verification Steps

### Health Checks

```bash
# Application health
argocd app list | grep -E "(Healthy|Synced)"

# Pod health
oc get pods -A | grep -v Running

# Service health
for svc in kafka-connect streamsage-api streamsage-console; do
  echo "Checking $svc..."
  oc exec -n kafka-dev deployment/$svc -- curl -f http://localhost:8080/health || echo "FAILED"
done
```

### Connectivity Tests

```bash
# Kafka connectivity
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9093

# Database connectivity
oc exec -n streamsage-dev deployment/streamsage-api -- \
  pg_isready -h postgres.streamsage-dev.svc.cluster.local

# External connectivity
curl -f https://streamsage-console.apps.cluster.example.com/health
```

### Performance Tests

```bash
# Kafka throughput test
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-producer-perf-test.sh \
  --topic streamsage.test \
  --num-records 10000 \
  --record-size 1024 \
  --throughput 1000 \
  --producer-props bootstrap.servers=localhost:9093

# API response time test
curl -w "@curl-format.txt" -o /dev/null -s https://streamsage-api.apps.cluster.example.com/health
```

---

## Troubleshooting

### Common Issues

#### ArgoCD Sync Failures

**Symptoms:**
- Application stuck in "Progressing" state
- Sync operation fails with errors

**Diagnosis:**
```bash
# Check application status
argocd app get <app-name>

# Check sync logs
argocd app logs <app-name>

# Check resource events
oc describe <resource-type> <resource-name> -n <namespace>
```

**Solutions:**
```bash
# Force refresh
argocd app refresh <app-name>

# Hard refresh (ignore cache)
argocd app refresh <app-name> --hard-refresh

# Manual sync with prune
argocd app sync <app-name> --prune --force
```

#### Pod Startup Failures

**Symptoms:**
- Pods stuck in "Pending" or "CrashLoopBackOff"
- Container restart loops

**Diagnosis:**
```bash
# Check pod status
oc get pods -n <namespace>

# Check pod logs
oc logs <pod-name> -n <namespace>

# Check pod events
oc describe pod <pod-name> -n <namespace>

# Check resource constraints
oc describe node <node-name>
```

**Solutions:**
```bash
# Resource constraints
oc patch deployment <deployment-name> -n <namespace> -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container-name>","resources":{"requests":{"memory":"512Mi","cpu":"200m"},"limits":{"memory":"1Gi","cpu":"500m"}}}]}}}}'

# Image pull issues
oc create secret docker-registry quay-secret \
  --docker-server=quay.io \
  --docker-username=<username> \
  --docker-password=<password> \
  -n <namespace>
```

#### Network Connectivity Issues

**Symptoms:**
- Services cannot communicate
- External access fails
- DNS resolution errors

**Diagnosis:**
```bash
# Check network policies
oc get networkpolicies -n <namespace>

# Test pod-to-pod connectivity
oc exec -n <namespace> <pod-name> -- nslookup <service-name>

# Check service endpoints
oc get endpoints -n <namespace>
```

**Solutions:**
```bash
# Temporarily disable network policies
oc delete networkpolicy default-deny-all -n <namespace>

# Check service selectors
oc get svc <service-name> -n <namespace> -o yaml

# Verify pod labels
oc get pods -n <namespace> --show-labels
```

### Emergency Contacts

| Role | Contact | Phone | Email |
|------|---------|-------|-------|
| Platform Team Lead | John Doe | +1-555-0101 | john.doe@company.com |
| SRE On-Call | Jane Smith | +1-555-0102 | jane.smith@company.com |
| Database Admin | Bob Johnson | +1-555-0103 | bob.johnson@company.com |
| Security Team | Alice Brown | +1-555-0104 | alice.brown@company.com |

### Escalation Procedures

1. **Level 1** (0-15 minutes): Platform team member
2. **Level 2** (15-30 minutes): Platform team lead + SRE
3. **Level 3** (30+ minutes): Management + vendor support

---

## Appendix

### Useful Commands

```bash
# Quick status check
alias k='kubectl'
alias oc-pods='oc get pods -A | grep -v Running'
alias argocd-apps='argocd app list | grep -v Healthy'

# Log aggregation
oc logs -f deployment/streamsage-api -n streamsage-dev | grep ERROR

# Resource usage
oc top pods -n kafka-dev
oc top nodes
```

### Configuration Files

- ArgoCD Projects: `deploy/apps/argocd/projects/`
- ApplicationSets: `deploy/apps/argocd/applicationsets/`
- Base Configurations: `deploy/apps/base/`
- Environment Overlays: `deploy/apps/overlays/`

### Monitoring URLs

- **Grafana:** https://grafana.apps.cluster.example.com
- **Prometheus:** https://prometheus.apps.cluster.example.com
- **ArgoCD:** https://argocd.apps.cluster.example.com
- **AlertManager:** https://alertmanager.apps.cluster.example.com

---

**Document Control:**
- **Version:** 1.0
- **Last Review:** 2026-03-21
- **Next Review:** 2026-06-21
- **Approved By:** Platform Team Lead