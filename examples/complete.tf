# Example: Complete ArgoCD deployment with all features
# 
# This example shows a full deployment with all optional features enabled

variable "github_token" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true
}

module "argocd_complete" {
  source = "../"
  
  # Required cluster configuration
  cluster_name   = "prod-cluster-01"
  gcp_project_id = "prod-project-01"
  gcp_region     = "us-central1"
  gcp_folder     = "production"
  environment    = "production"
  
  # ArgoCD version
  argocd_chart_version = "8.1.3"
  namespace_name      = "argocd"
  
  # Bootstrap configuration
  bootstrap_repo_url      = "https://github.com/YOUR-GITHUB-ORG/gitops-repository"
  bootstrap_repo_revision = "main"
  bootstrap_repo_private  = true
  github_token           = var.github_token
  
  # Ingress configuration
  cluster_domain      = "prod.example.com"
  ingress_prefix      = "prod"
  ingress_reserved_ip = "35.214.105.236"
  
  # Enable all optional features
  enable_oauth_groups_sa              = true
  enable_grafana_oauth_token_manager = true
}

# Provider configuration example
provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

# Data sources (example)
data "google_client_config" "default" {}

data "google_container_cluster" "primary" {
  name     = "prod-cluster-01"
  location = "us-central1"
  project  = "prod-project-01"
}

# Outputs
output "argocd_configuration" {
  description = "Complete ArgoCD configuration"
  value = {
    namespace     = module.argocd_complete.argocd_namespace
    helm_release  = module.argocd_complete.helm_release_name
    helm_version  = module.argocd_complete.helm_release_version
    cluster_name  = module.argocd_complete.cluster_name
  }
}

output "service_accounts" {
  description = "All created GCP service accounts"
  value = {
    argocd_server    = module.argocd_complete.argocd_server_service_account_email
    external_dns     = module.argocd_complete.external_dns_service_account_email
    cert_manager     = module.argocd_complete.cert_manager_service_account_email
    external_secrets = module.argocd_complete.external_secrets_service_account_email
    oauth_groups     = module.argocd_complete.oauth_groups_service_account_email
    monitoring       = module.argocd_complete.monitoring_service_account
  }
}

output "workload_identity" {
  description = "Workload Identity configuration"
  value       = module.argocd_complete.workload_identity_configuration
}

output "ingress_config" {
  description = "Ingress configuration and URLs"
  value       = module.argocd_complete.ingress_configuration
}

output "cluster_metadata" {
  description = "Cluster metadata for ApplicationSets"
  value       = module.argocd_complete.cluster_metadata
}

output "setup_instructions" {
  description = "Post-deployment setup instructions"
  value       = module.argocd_complete.setup_instructions
}