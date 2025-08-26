# Terraform ArgoCD Bootstrap Module

A comprehensive Terraform module for bootstrapping ArgoCD on Google Kubernetes Engine (GKE) with full GitOps capabilities, Workload Identity integration, and External Secrets management.

## Features

- **Minimal Bootstrap Approach**: Deploys ArgoCD with minimal configuration, allowing full GitOps-based management afterward
- **Workload Identity Integration**: Automatic creation and configuration of GCP service accounts for:
  - ArgoCD Server
  - External DNS
  - Cert Manager
  - External Secrets Operator
  - Monitoring (Grafana/Prometheus)
  - OAuth Groups (optional)
- **GitOps-First Design**: Bootstrap ApplicationSet automatically deployed for cluster self-management
- **Comprehensive Metadata**: Rich cluster metadata for dynamic ApplicationSet configuration
- **Private Repository Support**: GitHub token authentication for private GitOps repositories
- **Multi-Environment Support**: Optimized for development, staging, and production deployments

## Architecture

This module implements a bootstrap-first approach where:
1. Terraform deploys minimal ArgoCD configuration
2. ArgoCD immediately takes over its own management via GitOps
3. All further configuration happens through Git commits

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture documentation.

## Usage

### Basic Example

```hcl
module "argocd" {
  source = "github.com/YOUR-ORG/terraform-argocd-bootstrap-module"
  
  # Required cluster configuration
  cluster_name   = "dev-cluster-01"
  gcp_project_id = "dev-project-01"
  gcp_region     = "us-central1"
  gcp_folder     = "development"
  environment    = "development"
  
  # Bootstrap repository
  bootstrap_repo_url = "https://github.com/YOUR-ORG/gitops-repository"
}
```

### Private Repository Example

```hcl
module "argocd" {
  source = "github.com/YOUR-ORG/terraform-argocd-bootstrap-module"
  
  cluster_name   = "dev-cluster-01"
  gcp_project_id = "dev-project-01"
  gcp_region     = "us-central1"
  gcp_folder     = "development"
  environment    = "development"
  
  # Private repository configuration
  bootstrap_repo_url      = "https://github.com/YOUR-ORG/gitops-repository"
  bootstrap_repo_private  = true
  bootstrap_repo_revision = "main"
  github_token           = var.github_token  # Set via TF_VAR_github_token
  
  # Optional: Ingress configuration
  cluster_domain      = "dev.example.sslip.io"
  ingress_prefix      = "dev"
  ingress_reserved_ip = "35.214.105.236"
}
```

### Complete Example with All Features

See [examples/complete.tf](examples/complete.tf) for a comprehensive example with all features enabled.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| kubernetes | >= 2.24 |
| helm | >= 3.0 |
| google | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| kubernetes | >= 2.24 |
| helm | >= 3.0 |
| google | >= 5.0 |
| null | >= 3.0 |
| time | >= 0.9 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the GKE cluster | `string` | n/a | yes |
| gcp_project_id | GCP project ID | `string` | n/a | yes |
| gcp_region | GCP region | `string` | n/a | yes |
| gcp_folder | GCP folder name for environment classification | `string` | n/a | yes |
| environment | Environment designation (development/staging/production) | `string` | n/a | yes |
| argocd_chart_version | ArgoCD Helm chart version | `string` | `"8.1.3"` | no |
| namespace_name | Namespace for ArgoCD installation | `string` | `"argocd"` | no |
| bootstrap_repo_url | Git repository URL for bootstrap configuration | `string` | n/a | yes |
| bootstrap_repo_revision | Git branch/tag/revision for bootstrap repository | `string` | `"main"` | no |
| bootstrap_repo_private | Whether the bootstrap repository is private | `bool` | `true` | no |
| github_token | GitHub Personal Access Token for private repository access | `string` | `""` | no |
| cluster_domain | Domain for cluster ingress resources | `string` | `""` | no |
| ingress_prefix | Prefix for ingress hostnames | `string` | `""` | no |
| ingress_reserved_ip | Reserved static IP address for ingress LoadBalancer | `string` | `""` | no |
| enable_oauth_groups_sa | Enable OAuth Groups service account | `bool` | `false` | no |
| enable_grafana_oauth_token_manager | Enable OAuth token manager for Grafana | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| argocd_namespace | The namespace where ArgoCD is installed |
| helm_release_name | The name of the Helm release |
| helm_release_version | The version of the ArgoCD Helm chart deployed |
| cluster_name | The cluster name identifier |
| workload_identity_configuration | Complete Workload Identity configuration for all services |
| ingress_configuration | Ingress configuration including all service URLs |
| cluster_metadata | Cluster metadata used by ApplicationSets |
| setup_instructions | Post-deployment setup instructions |

## Service Accounts Created

This module creates the following GCP service accounts with Workload Identity bindings:

| Service Account | Purpose | IAM Roles | Kubernetes Service Account |
|-----------------|---------|-----------|----------------------------|
| `{cluster-id}-argocd-server` | ArgoCD Server operations | `roles/container.developer` | `argocd-server` in `argocd` namespace |
| `{cluster-id}-external-dns` | DNS record management | `roles/dns.admin` | `external-dns` in `external-dns` namespace |
| `{cluster-id}-cert-manager` | SSL certificate management | `roles/dns.admin` | `cert-manager` in `cert-manager` namespace |
| `{cluster-id}-external-secrets` | Secret management | `roles/secretmanager.secretAccessor` | `external-secrets` in `external-secrets` namespace |
| `{cluster-id}-monitoring` | Monitoring data access | `roles/monitoring.viewer` | `grafana` in `monitoring` namespace |
| `{cluster-id}-oauth-groups` | OAuth group management (optional) | `roles/cloudidentity.groups.reader` | `argocd-oauth` in `argocd` namespace |

## Post-Deployment Steps

1. **Wait for ArgoCD to be ready:**
   ```bash
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd
   ```

2. **Get initial admin password:**
   ```bash
   kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
   ```

3. **Access ArgoCD UI:**
   - Port-forward: `kubectl port-forward svc/argocd-server -n argocd 8080:443`
   - Or use the ingress URL if configured

4. **Configure External Secrets:**
   - Deploy External Secrets configuration from your GitOps repository
   - See [docs/EXTERNAL-SECRETS-MANAGEMENT.md](docs/EXTERNAL-SECRETS-MANAGEMENT.md)

5. **Configure OAuth and other settings:**
   - All configuration should be done via GitOps
   - Edit `argocd-helm/clusters/{environment}/{cluster}.yaml` in your GitOps repository

## GitOps Repository Structure

Your GitOps repository should follow this structure:

```
gitops-repository/
├── bootstrap/
│   └── root-app.yaml              # Root application
├── argocd-helm/
│   ├── values.yaml                # Base ArgoCD values
│   └── clusters/
│       ├── development/
│       │   └── dev-cluster-01.yaml
│       ├── staging/
│       │   └── staging-cluster-01.yaml
│       └── production/
│           └── prod-cluster-01.yaml
├── infrastructure/
│   ├── external-secrets-config/
│   ├── cert-manager/
│   └── external-dns/
└── applications/
    └── ... your applications ...
```

## Examples

- [Basic Deployment](examples/basic-deployment.tf) - Simple ArgoCD deployment
- [Private Repository](examples/private-repo-example.tf) - Using private GitHub repositories
- [Complete Setup](examples/complete.tf) - Full feature deployment
- [Multi-Cluster](examples/multi-cluster.tf) - Managing multiple clusters

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - System architecture and design decisions
- [Bootstrap Hierarchy](docs/BOOTSTRAP-HIERARCHY.md) - GitOps bootstrap structure
- [Configuration Metadata](docs/CONFIGURATION-METADATA-ARCHITECTURE.md) - Cluster metadata system
- [External Secrets Management](docs/EXTERNAL-SECRETS-MANAGEMENT.md) - Secret management guide

## Migration from Existing Setup

If migrating from an existing ArgoCD installation:

1. Export existing ArgoCD configuration
2. Ensure your GitOps repository follows the expected structure
3. Run this module with matching configuration
4. Verify ArgoCD picks up existing applications
5. Remove old ArgoCD installation

## Troubleshooting

### Private Repository Authentication Issues
- Ensure `github_token` is provided for private repositories
- Verify token has repository read access
- Check token format (must be `ghp_*` or `github_pat_*`)

### Bootstrap Application Not Created
- Check ArgoCD CRDs are installed: `kubectl get crd applicationsets.argoproj.io`
- Verify namespace exists: `kubectl get ns argocd`
- Check logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller`

### Workload Identity Issues
- Verify GKE Workload Identity is enabled on the cluster
- Check service account bindings: `gcloud iam service-accounts get-iam-policy {service-account}`
- Ensure Kubernetes service accounts have correct annotations

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This module is licensed under the Apache 2.0 License - see the LICENSE file for details.
