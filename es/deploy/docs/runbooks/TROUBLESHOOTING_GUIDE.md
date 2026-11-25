# StreamSage Troubleshooting Guide

**Version:** 1.0  
**Last Updated:** 2026-03-21  
**Owner:** Platform Team

---

## Overview

This guide provides detailed troubleshooting procedures for common StreamSage deployment and operational issues.

---

## Table of Contents

1. [Kafka Issues](#kafka-issues)
2. [Kafka Connect Issues](#kafka-connect-issues)
3. [StreamSage Service Issues](#streamsage-service-issues)
4. [Database Issues](#database-issues)
5. [Network Issues](#network-issues)
6. [ArgoCD Issues](#argocd-issues)
7. [Performance Issues](#performance-issues)
8. [Security Issues](#security-issues)

---

## Kafka Issues

### Issue: Kafka Broker Down

**Symptoms:**
- Kafka broker pod not running
- Producers/consumers cannot connect
- Alert: `KafkaBrokerDown`

**Diagnosis:**
```bash
# Check broker pods
oc get pods -n kafka-dev -l strimzi.io/name=kafka-es-kafka

# Check broker logs
oc logs -n kafka-dev kafka-es-kafka-0 --tail=100

# Check broker events
oc describe pod -n kafka-dev kafka-es-kafka-0

# Check persistent volume
oc get pvc -n kafka-dev
```

**Common Causes:**
1. Out of disk space
2. Memory pressure
3. Configuration errors
4. Network issues

**Solutions:**

**1. Disk Space Issues:**
```bash
# Check disk usage
oc exec -n kafka-dev kafka-es-kafka-0 -- df -h

# Clean up old log segments (if safe)
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-log-dirs.sh --describe --bootstrap-server localhost:9093

# Increase storage (if needed)
oc patch eventstreams kafka-es -n kafka-dev --type=merge -p '
spec:
  kafka:
    storage:
      size: 100Gi
'
```

**2. Memory Issues:**
```bash
# Check memory usage
oc top pod -n kafka-dev kafka-es-kafka-0

# Increase memory limits
oc patch eventstreams kafka-es -n kafka-dev --type=merge -p '
spec:
  kafka:
    resources:
      limits:
        memory: 4Gi
      requests:
        memory: 2Gi
'
```

**3. Restart Broker:**
```bash
# Delete pod (will be recreated)
oc delete pod -n kafka-dev kafka-es-kafka-0

# Wait for pod to be ready
oc wait --for=condition=Ready pod/kafka-es-kafka-0 -n kafka-dev --timeout=300s
```

### Issue: Under-Replicated Partitions

**Symptoms:**
- Data not fully replicated
- Alert: `KafkaUnderReplicatedPartitions`
- Potential data loss risk

**Diagnosis:**
```bash
# Check under-replicated partitions
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9093 --describe --under-replicated-partitions

# Check ISR status
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9093 --describe --topic streamsage.ingest.transaction
```

**Common Causes:**
1. Broker down or slow
2. Network issues
3. Disk I/O bottleneck
4. Replication lag

**Solutions:**

**1. Identify Slow Broker:**
```bash
# Check broker metrics
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9093

# Check replication lag
# Access Grafana dashboard: Kafka Overview
```

**2. Reassign Partitions:**
```bash
# Generate reassignment plan
cat > reassignment.json <<EOF
{
  "version": 1,
  "partitions": [
    {"topic": "streamsage.ingest.transaction", "partition": 0, "replicas": [0,1,2]}
  ]
}
EOF

# Execute reassignment
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-reassign-partitions.sh --bootstrap-server localhost:9093 \
  --reassignment-json-file /tmp/reassignment.json --execute
```

### Issue: High Consumer Lag

**Symptoms:**
- Messages not being consumed
- Alert: `KafkaHighConsumerLag`
- Processing delays

**Diagnosis:**
```bash
# Check consumer group lag
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9093 \
  --describe --group streamsage-consumer-group

# Check consumer status
oc get pods -n streamsage-dev -l app=streamsage-consumer
```

**Common Causes:**
1. Consumer pod down
2. Slow processing
3. Insufficient consumers
4. Network issues

**Solutions:**

**1. Scale Consumers:**
```bash
# Increase consumer replicas
oc scale deployment streamsage-consumer --replicas=5 -n streamsage-dev

# Verify scaling
oc get pods -n streamsage-dev -l app=streamsage-consumer
```

**2. Reset Consumer Offset (if safe):**
```bash
# Reset to latest
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9093 \
  --group streamsage-consumer-group --reset-offsets --to-latest --execute --all-topics

# Reset to specific offset
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9093 \
  --group streamsage-consumer-group --reset-offsets --to-offset 1000 --execute --topic streamsage.ingest.transaction
```

---

## Kafka Connect Issues

### Issue: Kafka Connect Cluster Down

**Symptoms:**
- Connect pods not running
- Connectors not working
- Alert: `KafkaConnectDown`

**Diagnosis:**
```bash
# Check Connect pods
oc get pods -n kafka-dev -l strimzi.io/name=kafka-connect

# Check Connect logs
oc logs -n kafka-dev deployment/kafka-connect --tail=100

# Check Connect REST API
oc exec -n kafka-dev deployment/kafka-connect -- \
  curl -s http://localhost:8083/
```

**Solutions:**

**1. Restart Connect Cluster:**
```bash
# Delete pods
oc delete pods -n kafka-dev -l strimzi.io/name=kafka-connect

# Wait for pods to be ready
oc wait --for=condition=Ready pods -l strimzi.io/name=kafka-connect -n kafka-dev --timeout=300s
```

**2. Check Configuration:**
```bash
# Verify KafkaConnect CR
oc get kafkaconnect kafka-connect -n kafka-dev -o yaml

# Check for configuration errors
oc describe kafkaconnect kafka-connect -n kafka-dev
```

### Issue: Connector Failed

**Symptoms:**
- Connector in FAILED state
- Data not flowing
- Alert: `KafkaConnectorFailed`

**Diagnosis:**
```bash
# List connectors
oc exec -n kafka-dev deployment/kafka-connect -- \
  curl -s http://localhost:8083/connectors

# Check connector status
oc exec -n kafka-dev deployment/kafka-connect -- \
  curl -s http://localhost:8083/connectors/postgres-sink/status | jq

# Check connector config
oc exec -n kafka-dev deployment/kafka-connect -- \
  curl -s http://localhost:8083/connectors/postgres-sink/config | jq
```

**Common Causes:**
1. Database connection issues
2. Schema mismatch
3. Permission errors
4. Configuration errors

**Solutions:**

**1. Restart Connector:**
```bash
# Restart connector
oc exec -n kafka-dev deployment/kafka-connect -- \
  curl -X POST http://localhost:8083/connectors/postgres-sink/restart

# Restart specific task
oc exec -n kafka-dev deployment/kafka-connect -- \
  curl -X POST http://localhost:8083/connectors/postgres-sink/tasks/0/restart
```

**2. Update Connector Configuration:**
```bash
# Update connector
cat > connector-config.json <<EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "2",
  "connection.url": "jdbc:postgresql://postgres:5432/streamsage",
  "connection.user": "streamsage",
  "connection.password": "password",
  "topics": "streamsage.ingest.transaction",
  "auto.create": "true"
}
EOF

oc exec -n kafka-dev deployment/kafka-connect -- \
  curl -X PUT -H "Content-Type: application/json" \
  --data @/tmp/connector-config.json \
  http://localhost:8083/connectors/postgres-sink/config
```

**3. Delete and Recreate:**
```bash
# Delete connector
oc exec -n kafka-dev deployment/kafka-connect -- \
  curl -X DELETE http://localhost:8083/connectors/postgres-sink

# Recreate connector
oc apply -f deploy/apps/base/kafka-connectors/postgres-sink-connector.yaml
```

---

## StreamSage Service Issues

### Issue: Service Pod CrashLooping

**Symptoms:**
- Pod repeatedly restarting
- Service unavailable
- Alert: `StreamSagePodRestartingFrequently`

**Diagnosis:**
```bash
# Check pod status
oc get pods -n streamsage-dev -l app=streamsage-api

# Check pod logs
oc logs -n streamsage-dev deployment/streamsage-api --tail=100

# Check previous logs
oc logs -n streamsage-dev deployment/streamsage-api --previous

# Check pod events
oc describe pod -n streamsage-dev <pod-name>
```

**Common Causes:**
1. Application errors
2. Configuration issues
3. Resource constraints
4. Health check failures

**Solutions:**

**1. Check Application Logs:**
```bash
# Stream logs
oc logs -f -n streamsage-dev deployment/streamsage-api

# Look for errors
oc logs -n streamsage-dev deployment/streamsage-api | grep -i error
```

**2. Adjust Health Probes:**
```bash
# Increase probe timeouts
oc patch deployment streamsage-api -n streamsage-dev --type=json -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds",
    "value": 60
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds",
    "value": 30
  }
]'
```

**3. Increase Resources:**
```bash
# Increase memory and CPU
oc patch deployment streamsage-api -n streamsage-dev --type=json -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/memory",
    "value": "2Gi"
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/cpu",
    "value": "1000m"
  }
]'
```

### Issue: High Error Rate

**Symptoms:**
- Many 5xx errors
- Alert: `StreamSageHighErrorRate`
- User complaints

**Diagnosis:**
```bash
# Check error logs
oc logs -n streamsage-dev deployment/streamsage-api | grep "HTTP/1.1 5"

# Check metrics
curl -s http://streamsage-api.streamsage-dev.svc.cluster.local:8080/metrics | grep http_requests_total

# Check database connectivity
oc exec -n streamsage-dev deployment/streamsage-api -- \
  pg_isready -h postgres.streamsage-dev.svc.cluster.local
```

**Solutions:**

**1. Check Dependencies:**
```bash
# Test Kafka connectivity
oc exec -n streamsage-dev deployment/streamsage-api -- \
  curl -s http://kafka-es-kafka-bootstrap.kafka-dev.svc.cluster.local:9093

# Test database connectivity
oc exec -n streamsage-dev deployment/streamsage-api -- \
  psql -h postgres.streamsage-dev.svc.cluster.local -U streamsage -c "SELECT 1"
```

**2. Review Recent Changes:**
```bash
# Check recent deployments
oc rollout history deployment/streamsage-api -n streamsage-dev

# Rollback if needed
oc rollout undo deployment/streamsage-api -n streamsage-dev
```

---

## Database Issues

### Issue: PostgreSQL Connection Pool Exhausted

**Symptoms:**
- Services cannot connect to database
- Alert: `PostgreSQLHighConnections`
- Connection timeout errors

**Diagnosis:**
```bash
# Check active connections
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Check connection limit
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -c "SHOW max_connections;"

# Check connections by application
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -c "SELECT application_name, count(*) FROM pg_stat_activity GROUP BY application_name;"
```

**Solutions:**

**1. Increase Connection Limit:**
```bash
# Update PostgreSQL configuration
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -c "ALTER SYSTEM SET max_connections = 200;"

# Restart PostgreSQL
oc rollout restart deployment/postgres -n streamsage-dev
```

**2. Optimize Application Connection Pools:**
```bash
# Update application configuration
oc set env deployment/streamsage-api -n streamsage-dev \
  DB_POOL_SIZE=10 \
  DB_POOL_MAX=20
```

### Issue: Slow Queries

**Symptoms:**
- High database latency
- Alert: `PostgreSQLSlowQueries`
- Application timeouts

**Diagnosis:**
```bash
# Check slow queries
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -c "SELECT pid, now() - pg_stat_activity.query_start AS duration, query FROM pg_stat_activity WHERE state = 'active' AND now() - pg_stat_activity.query_start > interval '5 seconds';"

# Check table statistics
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -d streamsage -c "SELECT schemaname, tablename, n_live_tup, n_dead_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC;"
```

**Solutions:**

**1. Analyze and Vacuum:**
```bash
# Analyze tables
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -d streamsage -c "ANALYZE;"

# Vacuum tables
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -d streamsage -c "VACUUM ANALYZE;"
```

**2. Add Indexes:**
```bash
# Identify missing indexes
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -d streamsage -c "SELECT schemaname, tablename, attname, n_distinct, correlation FROM pg_stats WHERE schemaname = 'public' ORDER BY n_distinct DESC LIMIT 10;"

# Create index (example)
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -d streamsage -c "CREATE INDEX CONCURRENTLY idx_transactions_created_at ON transactions(created_at);"
```

---

## Network Issues

### Issue: Network Policy Blocking Traffic

**Symptoms:**
- Services cannot communicate
- Connection refused errors
- Timeout errors

**Diagnosis:**
```bash
# Check network policies
oc get networkpolicies -n kafka-dev
oc get networkpolicies -n streamsage-dev

# Test connectivity
oc exec -n streamsage-dev deployment/streamsage-api -- \
  curl -v telnet://kafka-es-kafka-bootstrap.kafka-dev.svc.cluster.local:9093

# Check pod labels
oc get pods -n streamsage-dev --show-labels
```

**Solutions:**

**1. Temporarily Disable Network Policies:**
```bash
# Delete default-deny policy (for testing only)
oc delete networkpolicy default-deny-all -n streamsage-dev

# Test connectivity
# Re-apply policy after testing
oc apply -f deploy/apps/base/network-policies/default-deny-all.yaml
```

**2. Update Network Policy:**
```bash
# Add missing rule
oc patch networkpolicy streamsage-services-policy -n streamsage-dev --type=json -p='[
  {
    "op": "add",
    "path": "/spec/ingress/-",
    "value": {
      "from": [{"podSelector": {"matchLabels": {"app": "new-service"}}}],
      "ports": [{"protocol": "TCP", "port": 8080}]
    }
  }
]'
```

### Issue: DNS Resolution Failures

**Symptoms:**
- Cannot resolve service names
- "Name or service not known" errors

**Diagnosis:**
```bash
# Test DNS resolution
oc exec -n streamsage-dev deployment/streamsage-api -- \
  nslookup kafka-es-kafka-bootstrap.kafka-dev.svc.cluster.local

# Check CoreDNS pods
oc get pods -n openshift-dns

# Check DNS configuration
oc exec -n streamsage-dev deployment/streamsage-api -- cat /etc/resolv.conf
```

**Solutions:**

**1. Restart CoreDNS:**
```bash
# Restart DNS pods
oc delete pods -n openshift-dns -l dns.operator.openshift.io/daemonset-dns=default
```

**2. Use Fully Qualified Names:**
```bash
# Update service references to use FQDN
# Example: kafka-es-kafka-bootstrap.kafka-dev.svc.cluster.local
```

---

## ArgoCD Issues

### Issue: Application Out of Sync

**Symptoms:**
- Application shows "OutOfSync" status
- Changes not applied to cluster

**Diagnosis:**
```bash
# Check application status
argocd app get dev-event-streams

# Check diff
argocd app diff dev-event-streams

# Check sync status
argocd app list | grep OutOfSync
```

**Solutions:**

**1. Manual Sync:**
```bash
# Sync application
argocd app sync dev-event-streams --prune

# Force sync
argocd app sync dev-event-streams --force --prune
```

**2. Refresh Application:**
```bash
# Soft refresh
argocd app refresh dev-event-streams

# Hard refresh (ignore cache)
argocd app refresh dev-event-streams --hard-refresh
```

### Issue: Sync Operation Stuck

**Symptoms:**
- Sync operation never completes
- Application stuck in "Progressing" state

**Diagnosis:**
```bash
# Check sync operation
argocd app get dev-event-streams

# Check operation logs
argocd app logs dev-event-streams

# Check resource status
oc get all -n kafka-dev
```

**Solutions:**

**1. Terminate Sync Operation:**
```bash
# Terminate operation
argocd app terminate-op dev-event-streams
```

**2. Delete and Recreate Application:**
```bash
# Delete application (keeps resources)
argocd app delete dev-event-streams --cascade=false

# Recreate application
oc apply -f deploy/apps/argocd/applicationsets/event-streams-appset.yaml
```

---

## Performance Issues

### Issue: High Latency

**Symptoms:**
- Slow response times
- Alert: `StreamSageHighLatency`
- User complaints

**Diagnosis:**
```bash
# Check response times
curl -w "@curl-format.txt" -o /dev/null -s https://streamsage-api.apps.cluster.example.com/health

# Check resource usage
oc top pods -n streamsage-dev

# Check database performance
oc exec -n streamsage-dev deployment/postgres -- \
  psql -U postgres -d streamsage -c "SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"
```

**Solutions:**

**1. Scale Services:**
```bash
# Horizontal scaling
oc scale deployment streamsage-api --replicas=5 -n streamsage-dev

# Vertical scaling
oc patch deployment streamsage-api -n streamsage-dev --type=json -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/cpu",
    "value": "2000m"
  }
]'
```

**2. Enable Caching:**
```bash
# Deploy Redis
oc apply -f deploy/apps/base/redis/redis.yaml

# Update application to use cache
oc set env deployment/streamsage-api -n streamsage-dev \
  REDIS_HOST=redis.streamsage-dev.svc.cluster.local \
  CACHE_ENABLED=true
```

---

## Security Issues

### Issue: Unauthorized Access

**Symptoms:**
- 401/403 errors
- Access denied messages

**Diagnosis:**
```bash
# Check RBAC
oc get rolebindings -n streamsage-dev
oc get clusterrolebindings | grep streamsage

# Check service account
oc get sa -n streamsage-dev
oc describe sa streamsage-api -n streamsage-dev
```

**Solutions:**

**1. Update RBAC:**
```bash
# Create role binding
oc create rolebinding streamsage-api-binding \
  --clusterrole=edit \
  --serviceaccount=streamsage-dev:streamsage-api \
  -n streamsage-dev
```

**2. Check Secrets:**
```bash
# Verify secrets exist
oc get secrets -n streamsage-dev

# Check secret content
oc get secret streamsage-db-credentials -n streamsage-dev -o yaml
```

---

## Emergency Procedures

### Complete System Restart

```bash
# 1. Scale down all services
oc scale deployment --all --replicas=0 -n streamsage-dev

# 2. Restart Kafka
oc delete pods -n kafka-dev -l strimzi.io/name=kafka-es-kafka

# 3. Wait for Kafka to be ready
oc wait --for=condition=Ready pods -l strimzi.io/name=kafka-es-kafka -n kafka-dev --timeout=600s

# 4. Scale up services
oc scale deployment --all --replicas=3 -n streamsage-dev
```

### Data Recovery

```bash
# 1. Stop all consumers
oc scale deployment streamsage-consumer --replicas=0 -n streamsage-dev

# 2. Restore database
./deploy/scripts/restore-database.sh <backup-timestamp>

# 3. Reset consumer offsets
oc exec -n kafka-dev kafka-es-kafka-0 -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9093 \
  --group streamsage-consumer-group --reset-offsets --to-earliest --execute --all-topics

# 4. Restart consumers
oc scale deployment streamsage-consumer --replicas=3 -n streamsage-dev
```

---

## Getting Help

### Internal Resources
- **Runbooks:** `deploy/docs/runbooks/`
- **Architecture Docs:** `deploy/docs/architecture/`
- **Slack Channel:** #streamsage-support
- **Wiki:** https://wiki.company.com/streamsage

### External Resources
- **IBM Event Streams Docs:** https://ibm.github.io/event-streams/
- **Strimzi Docs:** https://strimzi.io/docs/
- **ArgoCD Docs:** https://argo-cd.readthedocs.io/
- **OpenShift Docs:** https://docs.openshift.com/

### Support Contacts
- **Platform Team:** platform-team@company.com
- **SRE On-Call:** +1-555-0100
- **IBM Support:** https://www.ibm.com/mysupport

---

**Document Control:**
- **Version:** 1.0
- **Last Review:** 2026-03-21
- **Next Review:** 2026-06-21
- **Approved By:** Platform Team Lead