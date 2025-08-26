# Example: Basic ArgoCD deployment
# 
# This example shows how to deploy ArgoCD using the minimal bootstrap approach.
# OAuth and other secrets are managed via External Secrets Operator.

module "argocd_basic" {
  source = "../"
  
  # Required cluster configuration
  cluster_name   = "dev-cluster-01"
  gcp_project_id = "dev-project-01"
  gcp_region     = "us-central1"
  gcp_folder     = "development"
  environment    = "development"
  
  # Bootstrap configuration
  bootstrap_repo_url = "https://github.com/YOUR-GITHUB-ORG/gitops-repository"
  
  # GitHub token only needed for private repository access during bootstrap
  # github_token = var.GITHUB_TOKEN  # From environment variable
}

# Outputs
output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = module.argocd_basic.argocd_namespace
}

output "service_accounts" {
  description = "Created GCP service accounts"
  value       = module.argocd_basic.workload_identity_configuration
}

output "next_steps" {
  description = "Post-deployment steps"
  value = {
    configure_oauth = "Configure OAuth in argocd-helm/clusters/${module.argocd_basic.cluster_name}.yaml"
    manage_secrets  = "Deploy External Secrets configuration from infrastructure/external-secrets-config/"
    check_status    = "kubectl get applications -n ${module.argocd_basic.argocd_namespace}"
  }
}