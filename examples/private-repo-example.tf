# Example: Deploying ArgoCD with Private GitHub Repository
# This example shows how to properly configure the module for private repositories

# Set GitHub token as environment variable before running:
# export TF_VAR_GITHUB_TOKEN="github_pat_xxxx"

variable "GITHUB_TOKEN" {
  description = "GitHub Personal Access Token from environment"
  type        = string
  sensitive   = true
}

module "argocd_private_repo" {
  source = "../"  # Or use remote source
  
  # Required cluster identification
  cluster_name   = "dev-cluster-02"
  gcp_project_id = "dev-project-01"
  gcp_region     = "us-central1"
  gcp_folder     = "development"
  environment    = "development"
  
  # Private repository configuration
  bootstrap_repo_url     = "https://github.com/YOUR-GITHUB-ORG/gitops-repository"
  bootstrap_repo_private = true  # Explicitly mark as private
  bootstrap_repo_revision = "main"
  
  # REQUIRED: GitHub token for private repository access
  github_token = var.GITHUB_TOKEN
  
  # Optional: Ingress configuration
  cluster_domain = "23d669ec.sslip.io"
  ingress_prefix = "dev-clone"
  ingress_reserved_ip = "35.214.105.236"
  
  # Optional: Enable additional service accounts
  enable_oauth_groups_sa = false
  enable_grafana_oauth_token_manager = false
}

# Outputs to verify configuration
output "argocd_namespace" {
  value = module.argocd_private_repo.argocd_namespace
}

output "bootstrap_status" {
  value = module.argocd_private_repo.bootstrap_application_deployed
}

output "ingress_urls" {
  value = module.argocd_private_repo.ingress_configuration.ingress_urls
}

output "important_note" {
  value = <<-EOT
    IMPORTANT: GitHub token is required for private repositories.
    
    If bootstrap fails with authentication errors:
    1. Ensure TF_VAR_GITHUB_TOKEN is set in environment
    2. Verify token has repository read access
    3. Check token format (ghp_* or github_pat_*)
    
    Current token status: ${var.GITHUB_TOKEN != "" ? "✓ Provided" : "✗ Missing"}
  EOT
}