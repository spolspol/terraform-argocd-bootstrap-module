# Core ArgoCD outputs
output "argocd_namespace" {
  description = "The namespace where ArgoCD is installed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}


output "helm_release_name" {
  description = "The name of the Helm release"
  value       = helm_release.argocd.name
}

output "helm_release_version" {
  description = "The version of the ArgoCD Helm chart deployed"
  value       = helm_release.argocd.version
}

output "cluster_name" {
  description = "The cluster name identifier"
  value       = local.cluster_name
}

# GCP Service Account outputs
output "argocd_server_service_account_email" {
  description = "ArgoCD server service account email for Workload Identity"
  value       = google_service_account.argocd_server.email
}

output "external_dns_service_account_email" {
  description = "External DNS service account email for Workload Identity"
  value       = google_service_account.external_dns.email
}

output "cert_manager_service_account_email" {
  description = "Cert Manager service account email for Workload Identity"
  value       = google_service_account.cert_manager.email
}

output "external_secrets_service_account_email" {
  description = "External Secrets service account email for Workload Identity"
  value       = google_service_account.external_secrets.email
}

output "oauth_groups_service_account_email" {
  description = "OAuth Groups service account email (only if enabled)"
  value       = var.enable_oauth_groups_sa ? google_service_account.oauth_groups_service_account[0].email : null
}

# Monitoring service account outputs
output "monitoring_service_account" {
  description = "Monitoring GCP service account details"
  value = {
    email         = google_service_account.monitoring.email
    account_id    = google_service_account.monitoring.account_id
    project       = var.gcp_project_id
    iam_role      = "roles/monitoring.viewer"
  }
}

output "monitoring_workload_identity_config" {
  description = "Workload Identity configuration for monitoring components"
  value = {
    monitoring_sa_annotation = {
      "iam.gke.io/gcp-service-account" = google_service_account.monitoring.email
    }
    namespace = "monitoring"
    kubernetes_service_accounts = [
      "grafana"
    ]
  }
}



# Workload Identity configuration outputs
output "workload_identity_configuration" {
  description = "Workload Identity service account configuration for cluster services"
  value = {
    argocd_server = {
      gcp_service_account_email  = google_service_account.argocd_server.email
      kubernetes_service_account = "argocd-server"
      namespace                 = var.namespace_name
      iam_roles                 = ["roles/container.developer"]
      workload_identity_binding  = "serviceAccount:${var.gcp_project_id}.svc.id.goog[${var.namespace_name}/argocd-server]"
    }
    
    external_dns = {
      gcp_service_account_email  = google_service_account.external_dns.email
      kubernetes_service_account = "external-dns"
      namespace                 = "external-dns"
      iam_roles                 = ["roles/dns.admin"]
      workload_identity_binding  = "serviceAccount:${var.gcp_project_id}.svc.id.goog[external-dns/external-dns]"
    }
    
    cert_manager = {
      gcp_service_account_email  = google_service_account.cert_manager.email
      kubernetes_service_account = "cert-manager"
      namespace                 = "cert-manager"
      iam_roles                 = ["roles/dns.admin"]
      workload_identity_binding  = "serviceAccount:${var.gcp_project_id}.svc.id.goog[cert-manager/cert-manager]"
    }
    
    external_secrets = {
      gcp_service_account_email  = google_service_account.external_secrets.email
      kubernetes_service_account = "external-secrets"
      namespace                 = "external-secrets"
      iam_roles                 = ["roles/secretmanager.secretAccessor"]
      workload_identity_binding  = "serviceAccount:${var.gcp_project_id}.svc.id.goog[external-secrets/external-secrets]"
    }
    
    oauth_groups = var.enable_oauth_groups_sa ? {
      gcp_service_account_email  = google_service_account.oauth_groups_service_account[0].email
      kubernetes_service_account = "argocd-oauth"
      namespace                 = var.namespace_name
      iam_roles                 = ["roles/cloudidentity.groups.reader"]
      workload_identity_binding  = "serviceAccount:${var.gcp_project_id}.svc.id.goog[${var.namespace_name}/argocd-oauth]"
    } : null
    
    monitoring = {
      gcp_service_account_email  = google_service_account.monitoring.email
      kubernetes_service_accounts = ["grafana"]
      namespace                 = "monitoring"
      iam_roles                 = ["roles/monitoring.viewer"]
      workload_identity_binding  = "serviceAccount:${var.gcp_project_id}.svc.id.goog[monitoring/grafana]"
      note                      = "Monitoring service account for accessing monitoring data"
    }
  }
}

# Bootstrap configuration output
output "bootstrap_application_deployed" {
  description = "Whether the bootstrap application was successfully deployed"
  value       = true  # Always deployed in per-cluster model
}

output "bootstrap_path" {
  description = "The Git path for bootstrap configuration"
  value       = "bootstrap"
}

# Ingress and networking configuration
output "ingress_configuration" {
  description = "Ingress configuration for cluster services"
  value = {
    reserved_ip_address = var.ingress_reserved_ip
    cluster_domain      = local.cluster_domain
    ingress_prefix      = local.ingress_prefix
    argocd_url         = "https://argo-${local.ingress_prefix}.${local.cluster_domain}"
    ingress_urls = {
      argocd        = "https://argo-${local.ingress_prefix}.${local.cluster_domain}"
      grafana       = "https://grafana-${local.ingress_prefix}.${local.cluster_domain}"
      karma         = "https://karma-${local.ingress_prefix}.${local.cluster_domain}"
      backend_api   = "https://api-${local.ingress_prefix}.${local.cluster_domain}"
      prometheus    = "https://prometheus-${local.ingress_prefix}.${local.cluster_domain}"
      alertmanager  = "https://alertmanager-${local.ingress_prefix}.${local.cluster_domain}"
    }
  }
}

# Cluster metadata configuration
output "cluster_metadata" {
  description = "Cluster metadata used by ApplicationSets"
  value = {
    cluster_name    = var.cluster_name
    cluster_id      = local.cluster_id
    project_name    = local.project_name
    environment     = var.gcp_folder
    gcp_project     = var.gcp_project_id
    gcp_region      = var.gcp_region
    reserved_ip     = var.ingress_reserved_ip
    cluster_domain  = local.cluster_domain
    ingress_prefix  = local.ingress_prefix
  }
}

# Setup instructions output
output "setup_instructions" {
  description = "Instructions for completing the ArgoCD setup"
  value = {
    argocd_access = {
      message           = "ArgoCD is configured via GitOps. Check argocd-helm/clusters/<env>/<cluster>.yaml for configuration."
      admin_password    = "kubectl get secret argocd-initial-admin-secret -n ${var.namespace_name} -o jsonpath='{.data.password}' | base64 -d"
      kubectl_access    = "kubectl port-forward svc/argocd-server -n ${var.namespace_name} 8080:443"
      web_access        = var.ingress_reserved_ip != "" ? "https://argo-${local.ingress_prefix}.${local.cluster_domain}" : "Configure ingress first"
    }
    
    gitops_configuration = {
      oauth_config      = "Configure OAuth in: argocd-helm/clusters/<env>/<cluster>.yaml"
      oauth_secrets     = "OAuth secrets managed via External Secrets - see infrastructure/external-secrets-config/"
      ingress_config    = "Configure ingress in: argocd-helm/clusters/<env>/<cluster>.yaml"
      resource_limits   = "Configure resources in: argocd-helm/values.yaml"
      secret_management = "See: docs/EXTERNAL-SECRETS-MANAGEMENT.md"
    }
    
    next_steps = [
      "1. Wait for ArgoCD to be ready: kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd",
      "2. ArgoCD will self-manage via the argocd application",
      "3. Configure External Secrets to provide OAuth credentials (see infrastructure/external-secrets-config/)",
      "4. Configure OAuth and ingress via GitOps in argocd-helm/",
      "5. All future changes should be made via GitOps, not Terraform"
    ]
  }
}