# Minimal ArgoCD configuration for bootstrap only
# All other configuration managed via GitOps in argocd-helm/

# Ensure consistent naming with self-management
fullnameOverride: "argocd"

# Basic configuration required for bootstrap
configs:
  cm:
    # Essential timeout for Git repository polling
    timeout.reconciliation: "180s"
    
    # Enable in-cluster mode (required)
    cluster.inClusterEnabled: "true"
    
    # Basic resource tracking
    application.resourceTrackingMethod: "annotation"
  
  # Repository configuration for bootstrap
  repositories:
    - url: ${bootstrap_repo_url}
      type: git
%{if github_auth_enabled~}
      # GitHub authentication for private repository access during bootstrap
      password: "${github_token}"
      username: not-used  # GitHub uses token as password
%{endif~}
  
  # Secret configuration
  # ArgoCD will create its default secret automatically
  # OAuth credentials are managed via External Secrets
  secret:
    createSecret: true

# Minimal server configuration
server:
  # Use ClusterIP - ingress configured via GitOps
  service:
    type: ClusterIP
  
  # Disable insecure mode
  insecure: false

# Enable only essential components for bootstrap
controller:
  # Application controller is required
  enabled: true

repoServer:
  # Repository server is required
  enabled: true

redis:
  # Redis is required for caching
  enabled: true

applicationSet:
  # ApplicationSet controller is required for GitOps patterns
  enabled: true

# Disable non-essential components during bootstrap
# These will be enabled via GitOps if needed
dex:
  enabled: false

notifications:
  enabled: false

# Note: All resource limits, replicas, metrics, ingress, OAuth configuration,
# and OAuth secrets are managed via GitOps in the argocd-helm directory