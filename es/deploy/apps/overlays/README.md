# StreamSage Kustomize Overlays

This directory contains Kustomize overlays for deploying StreamSage components across multiple environments.

## Directory Structure

```
overlays/
├── dev/              # Development environment
├── test/             # Testing environment
├── qa/               # Quality Assurance environment
├── staging/          # Staging environment (production-like)
├── perf/             # Performance testing environment
├── prod/             # Production environment
├── ep/               # Enterprise Production environment
├── eem/              # Enterprise Event Management environment
└── dr/               # Disaster Recovery environment
```

## Environment Characteristics

### Development (dev)
- **Purpose**: Local development and initial testing
- **Kafka Replicas**: 3
- **Storage**: 50Gi
- **Memory**: 4-8Gi per Kafka broker
- **License**: CloudPakForIntegrationNonProduction
- **Namespace**: kafka-dev, streamsage-dev

### Test (test)
- **Purpose**: Automated testing and CI/CD
- **Kafka Replicas**: 3
- **Storage**: 50Gi
- **Memory**: 4-8Gi per Kafka broker
- **License**: CloudPakForIntegrationNonProduction
- **Namespace**: kafka-test, streamsage-test

### Quality Assurance (qa)
- **Purpose**: QA validation and user acceptance testing
- **Kafka Replicas**: 3
- **Storage**: 100Gi
- **Memory**: 6-12Gi per Kafka broker
- **License**: CloudPakForIntegrationNonProduction
- **Namespace**: kafka-qa, streamsage-qa

### Staging (staging)
- **Purpose**: Pre-production validation with production-like configuration
- **Kafka Replicas**: 3
- **Storage**: 200Gi
- **Memory**: 8-16Gi per Kafka broker
- **License**: CloudPakForIntegrationProduction
- **Namespace**: kafka-staging, streamsage-staging

### Performance (perf)
- **Purpose**: Performance testing and load testing
- **Kafka Replicas**: 3
- **Storage**: 300Gi
- **Memory**: 12-24Gi per Kafka broker
- **License**: CloudPakForIntegrationProduction
- **Namespace**: kafka-perf, streamsage-perf

### Production (prod)
- **Purpose**: Production workloads
- **Kafka Replicas**: 3
- **Storage**: 200Gi
- **Memory**: 8-16Gi per Kafka broker
- **License**: CloudPakForIntegrationProduction
- **Namespace**: kafka-prod, streamsage-prod

### Enterprise Production (ep)
- **Purpose**: High-scale enterprise production workloads
- **Kafka Replicas**: 5
- **Storage**: 500Gi
- **Memory**: 16-32Gi per Kafka broker
- **License**: CloudPakForIntegrationProduction
- **Namespace**: kafka-ep, streamsage-ep

### Enterprise Event Management (eem)
- **Purpose**: Enterprise event management and monitoring
- **Kafka Replicas**: 3
- **Storage**: 150Gi
- **Memory**: 8-16Gi per Kafka broker
- **License**: CloudPakForIntegrationProduction
- **Namespace**: kafka-eem, streamsage-eem

### Disaster Recovery (dr)
- **Purpose**: Disaster recovery and business continuity
- **Kafka Replicas**: 3
- **Storage**: 200Gi
- **Memory**: 8-16Gi per Kafka broker
- **License**: CloudPakForIntegrationProduction
- **Namespace**: kafka-dr, streamsage-dr

## Component Structure

Each environment overlay contains the following components:

### 1. Event Streams (IBM Event Streams/Kafka)
- **Location**: `{env}/event-streams/`
- **Files**:
  - `kustomization.yaml` - References base and applies patches
  - `kafka-es-patch.yaml` - Environment-specific Kafka configuration

### 2. Kafka Connect
- **Location**: `{env}/kafka-connect/`
- **Files**:
  - `kustomization.yaml` - References base and applies patches
  - `kafka-connect-patch.yaml` - Environment-specific Kafka Connect configuration

### 3. Kafka Topics
- **Location**: `{env}/kafka-topics/`
- **Files**:
  - `kustomization.yaml` - References base topic definitions

### 4. StreamSage Console
- **Location**: `{env}/streamsage-console/`
- **Files**:
  - `kustomization.yaml` - References base and applies patches
  - `console-patch.yaml` - Environment-specific console configuration

## Deployment

### Prerequisites
- OpenShift cluster with appropriate permissions
- IBM Event Streams operator installed
- Kustomize CLI or `kubectl` with kustomize support

### Deploy to an Environment

```bash
# Deploy to development
kubectl apply -k deploy/apps/overlays/dev/event-streams
kubectl apply -k deploy/apps/overlays/dev/kafka-connect
kubectl apply -k deploy/apps/overlays/dev/kafka-topics
kubectl apply -k deploy/apps/overlays/dev/streamsage-console

# Or deploy all components at once
for component in event-streams kafka-connect kafka-topics streamsage-console; do
  kubectl apply -k deploy/apps/overlays/dev/$component
done
```

### Validate Configuration

```bash
# Preview what will be deployed (dry-run)
kubectl kustomize deploy/apps/overlays/dev/event-streams

# Check the generated manifests
kubectl kustomize deploy/apps/overlays/dev/event-streams | less
```

### Environment Promotion

Promote changes through environments in this order:
1. **dev** → Initial development and testing
2. **test** → Automated testing
3. **qa** → Quality assurance validation
4. **staging** → Pre-production validation
5. **perf** → Performance testing (parallel with staging)
6. **prod** → Production deployment
7. **ep** → Enterprise production (if needed)
8. **eem** → Enterprise event management (if needed)
9. **dr** → Disaster recovery (synchronized with prod)

## Configuration Management

### Resource Scaling Guidelines

| Environment | Kafka Replicas | Storage | Memory/Broker | CPU/Broker |
|-------------|----------------|---------|---------------|------------|
| dev         | 3              | 50Gi    | 4-8Gi         | 1-2        |
| test        | 3              | 50Gi    | 4-8Gi         | 1-2        |
| qa          | 3              | 100Gi   | 6-12Gi        | 1500m-3    |
| staging     | 3              | 200Gi   | 8-16Gi        | 2-4        |
| perf        | 3              | 300Gi   | 12-24Gi       | 3-6        |
| prod        | 3              | 200Gi   | 8-16Gi        | 2-4        |
| ep          | 5              | 500Gi   | 16-32Gi       | 4-8        |
| eem         | 3              | 150Gi   | 8-16Gi        | 2-4        |
| dr          | 3              | 200Gi   | 8-16Gi        | 2-4        |

### Kafka Configuration

Key Kafka settings that vary by environment:
- **Replication Factor**: 3 for all environments (high availability)
- **Min In-Sync Replicas**: 2 for all environments (data durability)
- **Network/IO Threads**: Increased for perf, ep environments
- **Storage Class**: `portworx-sc-repl-3` (3-way replication)

### Console Scaling

| Environment | Replicas | Memory    | CPU       |
|-------------|----------|-----------|-----------|
| dev         | 1        | 512Mi-1Gi | 500m-1    |
| test        | 1        | 512Mi-1Gi | 500m-1    |
| qa          | 2        | 512Mi-1Gi | 500m-1    |
| staging     | 3        | 1-2Gi     | 750m-1500m|
| perf        | 3        | 1536Mi-3Gi| 1-2       |
| prod        | 3        | 1-2Gi     | 750m-1500m|
| ep          | 5        | 2-4Gi     | 1-2       |
| eem         | 2        | 1-2Gi     | 750m-1500m|
| dr          | 3        | 1-2Gi     | 750m-1500m|

## Troubleshooting

### Common Issues

1. **Namespace doesn't exist**
   ```bash
   kubectl create namespace kafka-{env}
   kubectl create namespace streamsage-{env}
   ```

2. **Storage class not found**
   ```bash
   kubectl get storageclass
   # Update kafka-es-patch.yaml with available storage class
   ```

3. **Insufficient resources**
   ```bash
   kubectl describe nodes
   # Scale down replicas or adjust resource requests
   ```

4. **License issues**
   - Ensure correct license type for environment
   - Non-production: dev, test, qa
   - Production: staging, perf, prod, ep, eem, dr

### Validation Commands

```bash
# Check Event Streams status
kubectl get eventstreams -n kafka-{env}

# Check Kafka Connect status
kubectl get kafkaconnect -n kafka-{env}

# Check console deployment
kubectl get deployment streamsage-console -n streamsage-{env}

# View logs
kubectl logs -n kafka-{env} -l app.kubernetes.io/name=kafka
kubectl logs -n streamsage-{env} -l app=streamsage-console
```

## Best Practices

1. **Always test in lower environments first** (dev → test → qa → staging → prod)
2. **Use production licenses only for staging, perf, prod, ep, eem, dr**
3. **Monitor resource usage** and adjust requests/limits accordingly
4. **Keep disaster recovery (dr) synchronized** with production
5. **Document any environment-specific customizations**
6. **Use GitOps practices** for deployment automation
7. **Validate manifests** before applying: `kubectl kustomize <path> | kubectl apply --dry-run=client -f -`

## Support

For issues or questions:
- Check the base configurations in `deploy/apps/base/`
- Review OpenShift/Kubernetes logs
- Consult IBM Event Streams documentation
- Contact the StreamSage platform team