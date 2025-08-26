# Core cluster identification
variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
}

variable "gcp_folder" {
  description = "GCP folder name for environment classification"
  type        = string
}

# Environment classification (simplified)
variable "environment" {
  description = "Environment designation"
  type        = string
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

# ArgoCD deployment configuration
variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version (8.1.3+ recommended)"
  type        = string
  default     = "8.1.3"
}

variable "namespace_name" {
  description = "Namespace for ArgoCD installation"
  type        = string
  default     = "argocd"
}

# Bootstrap configuration (always enabled for per-cluster)
variable "bootstrap_repo_url" {
  description = "Git repository URL for bootstrap configuration"
  type        = string
  default     = "https://github.com/YOUR-GITHUB-ORG/gitops-repository"
}

variable "bootstrap_repo_revision" {
  description = "Git branch/tag/revision for bootstrap repository (e.g., main, develop, v1.0.0)"
  type        = string
  default     = "main"
  
  validation {
    condition     = length(var.bootstrap_repo_revision) > 0
    error_message = "Bootstrap revision cannot be empty."
  }
}

variable "bootstrap_repo_private" {
  description = "Whether the bootstrap repository is private (requires github_token)"
  type        = bool
  default     = true
}

# Cluster domain configuration
variable "cluster_domain" {
  description = "Domain for cluster ingress resources (e.g., 23d669ec.sslip.io)"
  type        = string
  default     = ""
}

variable "ingress_prefix" {
  description = "Prefix for ingress hostnames (e.g., 'dev' or 'dev-clone')"
  type        = string
  default     = ""
}

variable "ingress_reserved_ip" {
  description = "Reserved static IP address for ingress LoadBalancer (regional or global)"
  type        = string
  default     = ""
}

# Enable OAuth token manager workload identity binding for Grafana
variable "enable_grafana_oauth_token_manager" {
  description = "Enable OAuth token manager workload identity binding for Grafana"
  type        = bool
  default     = false
}

# Service account configuration
variable "enable_oauth_groups_sa" {
  description = "Enable creation of OAuth Groups service account (for backward compatibility)"
  type        = bool
  default     = false
}

# GitHub token for initial bootstrap repository access
# After bootstrap, all other secrets are managed via External Secrets
variable "github_token" {
  description = "GitHub Personal Access Token for initial bootstrap repository access (required for private repos)"
  type        = string
  sensitive   = true
  default     = ""
  
  validation {
    condition = can(regex("^(ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{82}|)$", var.github_token))
    error_message = "GitHub token must be a valid classic token (ghp_*) or fine-grained token (github_pat_*), or empty for public repositories."
  }
}