# Example: Multi-cluster ArgoCD deployment
# 
# This example shows how to deploy ArgoCD across multiple clusters

variable "github_token" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true
}

# Development cluster
module "argocd_dev" {
  source = "../"
  
  cluster_name   = "dev-cluster-01"
  gcp_project_id = "dev-project-01"
  gcp_region     = "us-central1"
  gcp_folder     = "development"
  environment    = "development"
  
  bootstrap_repo_url      = "https://github.com/YOUR-GITHUB-ORG/gitops-repository"
  bootstrap_repo_revision = "develop"
  bootstrap_repo_private  = true
  github_token           = var.github_token
  
  cluster_domain      = "dev.example.sslip.io"
  ingress_prefix      = "dev"
  ingress_reserved_ip = "35.214.105.236"
}

# Staging cluster
module "argocd_staging" {
  source = "../"
  
  cluster_name   = "staging-cluster-01"
  gcp_project_id = "staging-project-01"
  gcp_region     = "us-central1"
  gcp_folder     = "staging"
  environment    = "staging"
  
  bootstrap_repo_url      = "https://github.com/YOUR-GITHUB-ORG/gitops-repository"
  bootstrap_repo_revision = "staging"
  bootstrap_repo_private  = true
  github_token           = var.github_token
  
  cluster_domain      = "staging.example.sslip.io"
  ingress_prefix      = "staging"
  ingress_reserved_ip = "35.214.105.237"
}

# Production cluster
module "argocd_prod" {
  source = "../"
  
  cluster_name   = "prod-cluster-01"
  gcp_project_id = "prod-project-01"
  gcp_region     = "us-central1"
  gcp_folder     = "production"
  environment    = "production"
  
  bootstrap_repo_url      = "https://github.com/YOUR-GITHUB-ORG/gitops-repository"
  bootstrap_repo_revision = "main"
  bootstrap_repo_private  = true
  github_token           = var.github_token
  
  cluster_domain      = "prod.example.com"
  ingress_prefix      = "prod"
  ingress_reserved_ip = "35.214.105.238"
  
  # Production-specific features
  enable_oauth_groups_sa = true
}

# Outputs for all clusters
output "clusters" {
  description = "All cluster configurations"
  value = {
    development = {
      namespace = module.argocd_dev.argocd_namespace
      url       = module.argocd_dev.ingress_configuration.argocd_url
      metadata  = module.argocd_dev.cluster_metadata
    }
    staging = {
      namespace = module.argocd_staging.argocd_namespace
      url       = module.argocd_staging.ingress_configuration.argocd_url
      metadata  = module.argocd_staging.cluster_metadata
    }
    production = {
      namespace = module.argocd_prod.argocd_namespace
      url       = module.argocd_prod.ingress_configuration.argocd_url
      metadata  = module.argocd_prod.cluster_metadata
    }
  }
}

output "next_steps" {
  value = <<-EOT
    Multi-cluster ArgoCD deployment complete!
    
    Access URLs:
    - Development: ${module.argocd_dev.ingress_configuration.argocd_url}
    - Staging: ${module.argocd_staging.ingress_configuration.argocd_url}
    - Production: ${module.argocd_prod.ingress_configuration.argocd_url}
    
    Next steps:
    1. Configure External Secrets in each cluster
    2. Set up OAuth for each environment
    3. Configure cross-cluster application management if needed
    4. Review GitOps repository structure for multi-cluster support
  EOT
}