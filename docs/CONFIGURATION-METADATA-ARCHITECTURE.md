# Configuration Metadata Architecture

## Overview

This document describes the configuration metadata architecture implemented in the ArgoCD GitOps platform. The architecture enables dynamic, flexible configuration management through a 3-tier hierarchy, cluster metadata labels, and matrix generators that provide branch-based deployment capabilities.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [3-Tier Configuration Hierarchy](#3-tier-configuration-hierarchy)
3. [Cluster Metadata System](#cluster-metadata-system)
4. [Matrix Generator Pattern](#matrix-generator-pattern)
5. [Dynamic Revision Support](#dynamic-revision-support)
6. [Branch-Based Deployment](#branch-based-deployment)
7. [Implementation Examples](#implementation-examples)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

## Architecture Overview

The configuration metadata architecture transforms how ArgoCD manages multi-cluster deployments by introducing:

- **3-Tier Hierarchy**: Base → Environment → Cluster configuration inheritance
- **Metadata-Driven**: Cluster labels control all dynamic behavior
- **Matrix Generators**: Enable ApplicationSets to access cluster metadata
- **Branch Testing**: Deploy feature branches to specific clusters
- **Zero Duplication**: Share configurations at the appropriate level

### Key Benefits

1. **Dynamic Flexibility**: All clusters can track different Git branches
2. **Testing Isolation**: Test changes without affecting other clusters
3. **Clear Precedence**: Explicit override hierarchy
4. **GitOps Native**: Everything controlled through Git

## 3-Tier Configuration Hierarchy

### Hierarchy Levels

```
┌─────────────────────────────────────────────┐
│ Level 3: Cluster-Specific Overrides         │
│ Path: clusters/{env}/{cluster}/values/      │
│ Purpose: Cluster-unique settings            │
│ Example: Domain names, resource limits      │
└─────────────────────────────────────────────┘
                    ↑ Overrides
┌─────────────────────────────────────────────┐
│ Level 2: Environment-Wide Defaults          │
│ Path: clusters/{environment}/values/        │
│ Purpose: Shared environment settings        │
│ Example: Dev resource profiles, staging TLS │
└─────────────────────────────────────────────┘
                    ↑ Overrides
┌─────────────────────────────────────────────┐
│ Level 1: Base Configuration                 │
│ Path: {service}/values.yaml                 │
│ Purpose: Universal defaults                 │
│ Example: Image versions, health checks      │
└─────────────────────────────────────────────┘
```

### Directory Structure

```
clusters/
├── development/
│   ├── values/                   # Environment defaults (Level 2)
│   │   ├── ingress-nginx.yaml    # Shared across all dev clusters
│   │   ├── cert-manager.yaml
│   │   └── prometheus-stack.yaml
│   ├── dev-cluster-01/
│   │   └── values/               # Cluster overrides (Level 3)
│   │       └── ingress-nginx.yaml # Only cluster-specific settings
│   └── dev-cluster-02/
│       └── values/
├── staging/
│   ├── values/                   # Staging environment defaults
│   └── staging-01-ue1-cluster-01/
└── production/
    ├── values/                   # Production environment defaults
    └── prod-cluster-01/
```

### Value File Resolution

ApplicationSets apply values in this order:

```yaml
helm:
  valueFiles:
  # 1. Base configuration (always exists)
  - 'values.yaml'
  
  # 2. Environment type values (optional)
  - 'values-{{index .metadata.labels "env-type"}}.yaml'
  
  # 3. Environment-level values (NEW - shared across clusters)
  - '../../../{{index .metadata.labels "env-values-path"}}/{{.name}}.yaml'
  
  # 4. Cluster-specific values (overrides environment)
  - '../../../{{index .metadata.labels "cluster-values-path"}}/{{.name}}.yaml'
  
  # Important: Don't fail if files don't exist
  ignoreMissingValueFiles: true
```

## Cluster Metadata System

### Terraform-Managed Labels

The Terraform module creates cluster metadata that drives all dynamic behavior:

```hcl
# terraform/modules/argocd/main.tf
resource "kubernetes_secret" "argocd_cluster_metadata" {
  metadata {
    name      = "in-cluster"
    namespace = "argocd"
    labels = {
      # Required for cluster generator
      "argocd.argoproj.io/secret-type" = "cluster"
      
      # Custom metadata for configuration
      "cluster-name"       = var.cluster_name
      "environment"        = var.gcp_folder
      "env-type"           = var.gcp_folder == "production" ? "prod" : "non-prod"
      "env-values-path"    = "clusters/${var.gcp_folder}/values"
      "cluster-values-path" = "clusters/${var.gcp_folder}/${var.cluster_name}/values"
      "target-revision"    = var.bootstrap_repo_revision
    }
  }
}
```

### ConfigMap for Reference

```hcl
resource "kubernetes_config_map" "argocd_cluster_config" {
  metadata {
    name = "argocd-cluster-config"
  }
  data = {
    cluster-name = var.cluster_name
    environment  = var.gcp_folder
    gitops-target-revision = var.bootstrap_repo_revision
  }
}
```

## Matrix Generator Pattern

### What Are Matrix Generators?

Matrix generators combine outputs from two child generators, creating all possible combinations. This enables ApplicationSets to access both service definitions AND cluster metadata.

### Basic Pattern

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  generators:
  - matrix:
      generators:
      # First generator: Service/component list
      - list:
          elements:
          - name: cert-manager
            path: infrastructure/services/cert-manager
      
      # Second generator: Cluster metadata
      - clusters:
          selector:
            matchLabels:
              argocd.argoproj.io/secret-type: cluster
```

### Available Variables

From the cluster generator:
- `{{.server}}` - Cluster API server URL
- `{{.name}}` - Cluster name (usually "in-cluster")
- `{{.metadata.labels.*}}` - All cluster labels
- `{{index .metadata.labels "label-name"}}` - Labels with special characters

## Dynamic Revision Support

### How It Works

All ApplicationSets use the cluster's `target-revision` label:

```yaml
spec:
  source:
    targetRevision: '{{index .metadata.labels "target-revision" | default "main"}}'
```

### Supported ApplicationSets

**Bootstrap ApplicationSets**:
- `system.yaml` - Uses matrix generator ✓
- `argocd-self.yaml` - Uses matrix generator ✓
- `dynamic-overlays.yaml` - Uses matrix generator ✓
- `infrastructure.yaml` - Converted to ApplicationSet ✓
- `applications.yaml` - Converted to ApplicationSet ✓

**Infrastructure/Application ApplicationSets**:
- All use matrix generators and support dynamic revision

### Changing Target Branch

```bash
# Update cluster to track a different branch
kubectl label secret in-cluster -n argocd \
  target-revision=feature-branch --overwrite

# Verify the change
kubectl get secret in-cluster -n argocd -o jsonpath='{.metadata.labels.target-revision}'
```

## Branch-Based Deployment

### Use Cases

1. **Feature Testing**: Deploy feature branches to development clusters
2. **Staged Rollout**: Test in dev → staging → production
3. **Hotfix Testing**: Validate fixes in isolation
4. **A/B Testing**: Run different versions on different clusters

### Workflow Example

```bash
# 1. Create feature branch
git checkout -b feature/new-service
git push origin feature/new-service

# 2. Deploy to test cluster
terraform apply \
  -var="cluster_name=dev-cluster-02" \
  -var="bootstrap_repo_revision=feature/new-service"

# 3. Test and iterate
# Make changes, commit, push
# ArgoCD automatically syncs

# 4. Promote to main
git checkout main
git merge feature/new-service

# 5. Update cluster to main
terraform apply \
  -var="cluster_name=dev-cluster-02" \
  -var="bootstrap_repo_revision=main"
```

## Dynamic Overlays ApplicationSet

The `dynamic-overlays.yaml` ApplicationSet provides automatic discovery and deployment of Kustomize overlays:

### How It Works

1. **Discovery**: Git generator finds all `overlay-config.yaml` files
2. **Matrix Generation**: Combines discoveries with cluster metadata
3. **Dynamic Deployment**: Creates Applications with cluster-specific settings

### Example Overlay Configuration

```yaml
# clusters/development/dev-cluster-01/overlays/analytics-data-processor/overlay-config.yaml
app: analytics-data-processor
namespace: analytics-data-processor
cluster: dev-cluster-01
environment: development
level: cluster  # or 'environment' for shared overlays
project: applications
```

### Generated Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: analytics-data-processor-dev-cluster-01-overlay
spec:
  source:
    repoURL: https://github.com/YOUR-GITHUB-ORG/gke-argocd-cluster-gitops-poc
    targetRevision: '{{index .metadata.labels "target-revision" | default "main"}}'
    path: clusters/development/dev-cluster-01/overlays/analytics-data-processor
    kustomize: {}
  destination:
    name: dev-cluster-01
    namespace: analytics-data-processor
```

### Benefits

- **Zero Manual Configuration**: Overlays discovered automatically
- **Environment Support**: Share overlays across clusters
- **Branch Testing**: Each overlay tracks cluster's branch
- **Kustomize Native**: Full patching capabilities

## Implementation Examples

### Example 1: Shared Development Resources

**Environment Default** (`clusters/development/values/prometheus-stack.yaml`):
```yaml
kube-prometheus-stack:
  prometheus:
    prometheusSpec:
      resources:
        requests:
          cpu: 300m      # Reduced for all dev clusters
          memory: 768Mi  # 50% of production
```

**Cluster Override** (`clusters/development/dev-cluster-01/values/prometheus-stack.yaml`):
```yaml
kube-prometheus-stack:
  prometheus:
    prometheusSpec:
      externalLabels:
        cluster: dev-cluster-01  # Only cluster-specific
```

### Example 2: ApplicationSet with Full Hierarchy

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure-services
spec:
  generators:
  - matrix:
      generators:
      - list:
          elements:
          - name: ingress-nginx
            namespace: ingress-nginx
      - clusters:
          selector:
            matchLabels:
              argocd.argoproj.io/secret-type: cluster
  template:
    spec:
      source:
        helm:
          valueFiles:
          - 'values.yaml'
          - 'values-{{index .metadata.labels "env-type"}}.yaml'
          - '../../../{{index .metadata.labels "env-values-path"}}/{{.name}}.yaml'
          - '../../../{{index .metadata.labels "cluster-values-path"}}/{{.name}}.yaml'
          ignoreMissingValueFiles: true
```

## Complete Bootstrap Flow with Dynamic Revision

### Bootstrap Sequence

1. **Terraform Deployment**:
   ```hcl
   # Sets cluster branch via variable
   bootstrap_repo_revision = "feature/new-service"
   ```

2. **Root Application** (Created by Terraform):
   - Uses `${var.bootstrap_repo_revision}` directly
   - Deploys all bootstrap ApplicationSets

3. **Bootstrap ApplicationSets** (100% matrix generators):
   ```
   system.yaml          → Matrix (list + cluster) → Dynamic revision
   infrastructure-apps  → Matrix (list + cluster) → Dynamic revision
   applications.yaml    → Matrix (list + cluster) → Dynamic revision
   argocd-self.yaml    → Matrix (list + cluster) → Dynamic revision
   dynamic-overlays    → Matrix (git + cluster)  → Dynamic revision
   ```

4. **All Generated Applications**:
   - Inherit `targetRevision` from cluster metadata
   - Track the same branch as the cluster

### Visual Flow

```
Terraform Variable
    ↓
bootstrap_repo_revision = "feature/xyz"
    ↓
Root Application (targetRevision: feature/xyz)
    ↓
All ApplicationSets read cluster metadata
    ↓
Every generated App uses: {{index .metadata.labels "target-revision"}}
    ↓
Entire platform tracks feature/xyz branch
```
## Best Practices

### 1. Configuration Placement

- **Base Values**: Universal settings, image versions
- **Environment Values**: Resource profiles, shared domains
- **Cluster Values**: Unique identifiers, specific overrides

### 2. Testing Changes

1. Always test on non-production cluster first
2. Use branch deployment for significant changes
3. Monitor ApplicationSet generation after changes
4. Verify with: `./scripts/verify-dynamic-revision.sh`

### 3. Naming Conventions

- Environment values: Match service name exactly
- Use consistent naming across all levels
- Document any deviations

## Troubleshooting

### Issue: ApplicationSet Not Using Dynamic Revision

**Check matrix generator**:
```bash
kubectl get applicationset <name> -n argocd -o yaml | grep -A20 generators
```

**Verify cluster labels**:
```bash
kubectl get secret in-cluster -n argocd -o jsonpath='{.metadata.labels}' | jq
```

### Issue: Values Not Applied

**Check file paths**:
```bash
# From service directory, count "../"
# Should be 3 levels to reach repository root
```

**Verify label paths**:
```bash
kubectl get secret in-cluster -n argocd -o jsonpath='{.metadata.labels.env-values-path}'
```

### Issue: Wrong Branch Deployed

**Check all sources**:
1. Terraform variable: `bootstrap_repo_revision`
2. Cluster label: `target-revision`
3. Git generator revision (must be static for discovery)

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Overall system architecture
- [BOOTSTRAP-HIERARCHY.md](BOOTSTRAP-HIERARCHY.md) - Bootstrap flow details
- [scripts/verify-dynamic-revision.sh](../scripts/verify-dynamic-revision.sh) - Verification tool
