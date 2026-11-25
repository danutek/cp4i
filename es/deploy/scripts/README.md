# StreamSage Deployment Scripts

This directory contains validation and deployment scripts for the StreamSage platform.

## Validation Scripts

### validate-yaml.sh
Validates all YAML files in the deploy directory for syntax errors.

**Requirements:**
- Python 3
- PyYAML library

**Usage:**
```bash
./deploy/scripts/validate-yaml.sh
```

**What it checks:**
- YAML syntax validity
- File parsing errors
- Structural issues

### validate-kustomize.sh
Validates that all Kustomize overlays can build successfully.

**Requirements:**
- kubectl with Kustomize support

**Usage:**
```bash
./deploy/scripts/validate-kustomize.sh
```

**What it checks:**
- Kustomize build success
- Base and overlay compatibility
- Resource references
- Missing namespaces (warning)
- Missing resource limits (warning)

### validate-resources.sh
Validates Kubernetes resource configurations for best practices.

**Requirements:**
- bash
- grep, awk

**Usage:**
```bash
./deploy/scripts/validate-resources.sh
```

**What it checks:**
- Resource limits and requests
- Security contexts
- Health probes (liveness/readiness)
- Replica counts for HA
- Storage configurations
- Namespace specifications
- Label definitions

### validate-all.sh
Master script that runs all validation checks.

**Usage:**
```bash
./deploy/scripts/validate-all.sh
```

**Exit codes:**
- 0: All validations passed
- 1: One or more validations failed

## Running Validations

### Local Development

Before committing changes:
```bash
# Make scripts executable
chmod +x deploy/scripts/*.sh

# Run all validations
./deploy/scripts/validate-all.sh
```

### CI/CD Pipeline

Validations run automatically in GitHub Actions on:
- Push to main/develop branches
- Pull requests to main/develop branches
- Changes to deploy/ directory

See `.github/workflows/deploy-validation.yml` for details.

## Validation Best Practices

### 1. Run Before Committing
Always run validations locally before pushing:
```bash
./deploy/scripts/validate-all.sh
```

### 2. Fix Warnings
While warnings don't fail the build, they indicate potential issues:
- Missing resource limits → Add limits to prevent resource exhaustion
- Missing health probes → Add probes for better reliability
- Single replica → Consider HA for production

### 3. Understand Failures
If validation fails:
1. Read the error message carefully
2. Check the specific file mentioned
3. Fix the issue
4. Re-run validation

### 4. Test Kustomize Builds
Test specific overlays:
```bash
kubectl kustomize deploy/apps/overlays/dev/event-streams
```

## Common Issues and Solutions

### YAML Syntax Errors

**Issue:** Invalid YAML syntax
```
Error: mapping values are not allowed here
```

**Solution:** Check indentation and structure
```yaml
# Wrong
key:value

# Correct
key: value
```

### Kustomize Build Failures

**Issue:** Resource not found
```
Error: unable to find one or more resources
```

**Solution:** Check that base resources exist and paths are correct in kustomization.yaml

### Missing Resource Limits

**Issue:** Warning about missing resource limits

**Solution:** Add resource limits to Deployment/StatefulSet:
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### Missing Health Probes

**Issue:** Warning about missing health probes

**Solution:** Add liveness and readiness probes:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
```

## Script Maintenance

### Adding New Validations

To add a new validation:

1. Create a new script in `deploy/scripts/`
2. Follow the naming convention: `validate-*.sh`
3. Use consistent output format (colors, symbols)
4. Add to `validate-all.sh`
5. Update this README
6. Add to CI/CD pipeline if needed

### Script Template

```bash
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TOTAL=0
PASSED=0
FAILED=0

echo "=========================================="
echo "Your Validation Name"
echo "=========================================="

# Your validation logic here

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo -e "Total:  $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}❌ Validation failed!${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Validation passed!${NC}"
    exit 0
fi
```

## Integration with ArgoCD

These validations ensure that:
- YAML files are syntactically correct
- Kustomize builds succeed
- Resources follow best practices

ArgoCD will:
1. Pull changes from Git
2. Build Kustomize overlays
3. Apply to cluster
4. Monitor sync status

If validations pass locally, ArgoCD sync should succeed.

## Troubleshooting

### Script Permission Denied

```bash
chmod +x deploy/scripts/*.sh
```

### Python/PyYAML Not Found

```bash
pip3 install pyyaml
```

### kubectl Not Found

Install kubectl:
```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

## References

- [Kustomize Documentation](https://kustomize.io/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [StreamSage Migration Guide](../MIGRATION_GUIDE.md)