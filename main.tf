# Local values for consistent naming
locals {
  cluster_name     = var.cluster_name
  # Extract cluster identifier (cluster-01) from full cluster name for service account naming
  cluster_id       = regex("(cluster-\\d+)$", var.cluster_name)[0]
  # Extract project name (dev-01) from project ID (dev-01-a) for resource naming
  project_name     = regex("^([^-]+-[0-9]+)", var.gcp_project_id)[0]
  
  # Cluster domain configuration - use provided value or generate default
  cluster_domain   = var.cluster_domain != "" ? var.cluster_domain : "${local.cluster_id}.example.sslip.io"
  # Ingress prefix - use provided value or generate based on cluster ID
  ingress_prefix   = var.ingress_prefix != "" ? var.ingress_prefix : (local.cluster_id == "cluster-02" ? "dev-clone" : "dev")
  
  # GitHub authentication for private repository access during bootstrap
  github_auth_enabled = var.github_token != ""
}

# Validation: Ensure GitHub token is provided for private repositories
resource "null_resource" "validate_github_token" {
  count = var.bootstrap_repo_private && !local.github_auth_enabled ? 1 : 0
  
  provisioner "local-exec" {
    command = "echo 'ERROR: GitHub token is required for private repository ${var.bootstrap_repo_url}. Please provide github_token variable.' && exit 1"
  }
}

# ArgoCD Helm deployment - minimal bootstrap configuration
# All advanced configuration managed via GitOps in argocd-helm/
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = var.namespace_name
  
  create_namespace = true
  
  # Use minimal values for bootstrap only
  values = [
    templatefile("${path.module}/templates/minimal-bootstrap.yaml.tpl", {
      bootstrap_repo_url   = var.bootstrap_repo_url
      github_auth_enabled  = local.github_auth_enabled
      github_token        = var.github_token
    })
  ]
  
  depends_on = [
    kubernetes_namespace.argocd,
    kubernetes_config_map.argocd_cluster_config,
    kubernetes_secret.argocd_cluster_metadata,
    null_resource.validate_github_token
  ]
}

# Namespace creation
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace_name
    labels = {
      "name"                               = var.namespace_name
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

# ArgoCD cluster metadata ConfigMap for dynamic cluster identification
# Provides comprehensive metadata in structured format for applications
resource "kubernetes_config_map" "argocd_cluster_config" {
  metadata {
    name      = "argocd-cluster-config"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "app.kubernetes.io/part-of" = "argocd"
      "app.kubernetes.io/component" = "cluster-config"
    }
  }
  
  data = {
    # Legacy flat structure for backward compatibility
    cluster-name = var.cluster_name
    environment  = var.gcp_folder
    gcp-project  = var.gcp_project_id
    gcp-region   = var.gcp_region
    target-revision = var.bootstrap_repo_revision
    
    # Comprehensive metadata in YAML format for easy consumption
    "metadata.yaml" = yamlencode({
      cluster = {
        name         = var.cluster_name
        type         = var.gcp_folder == "production" ? "primary" : "workload"
        environment  = var.gcp_folder
        environmentType = var.gcp_folder == "production" ? "prod" : "non-prod"
      }
      gcp = {
        projectId    = var.gcp_project_id
        folder       = var.gcp_folder
        region       = var.gcp_region
      }
      paths = {
        envValues    = "clusters/${var.gcp_folder}/values"
        envOverlays  = "clusters/${var.gcp_folder}/overlays"
        clusterValues = "clusters/${var.gcp_folder}/${var.cluster_name}/values"
        clusterOverlays = "clusters/${var.gcp_folder}/${var.cluster_name}/overlays"
      }
      gitops = {
        targetRevision = var.bootstrap_repo_revision
        repoUrl       = var.bootstrap_repo_url
      }
      features = {
        highAvailability = var.gcp_folder == "production"
        resourceProfile  = var.gcp_folder == "production" ? "high" : "low"
        syncWaveOffset   = var.gcp_folder == "production" ? 100 : 0
      }
    })
  }
}

# Create cluster secret with actual cluster name and comprehensive metadata labels
# This enables ApplicationSets to dynamically determine cluster paths and configurations
resource "kubernetes_secret" "argocd_cluster_metadata" {
  metadata {
    name      = var.cluster_name  # Use actual cluster name instead of "in-cluster"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      # Required for cluster generator
      "argocd.argoproj.io/secret-type" = "cluster"
      
      # Standard labels for backward compatibility
      "cluster-name"       = var.cluster_name
      "environment"        = var.gcp_folder
      
      # Enhanced metadata for dynamic configuration
      "env-type"           = var.gcp_folder == "production" ? "prod" : "non-prod"
      "gcp-project"        = var.gcp_project_id
      "gcp-region"         = var.gcp_region
      "cluster-type"       = var.gcp_folder == "production" ? "primary" : "workload"
      
      # Extracted identifiers for simplified ApplicationSet templates
      "project-name"       = local.project_name
      "cluster-id"         = local.cluster_id
      
      # Ingress configuration for dynamic hostname generation
      "cluster-domain"     = local.cluster_domain
      "ingress-prefix"     = local.ingress_prefix
      "ingress-ip-address" = var.ingress_reserved_ip
      
      # Git revision for dynamic branch support
      "target-revision"    = var.bootstrap_repo_revision
    }
    annotations = {
      # Path helpers for ApplicationSets (moved from labels due to / character restrictions)
      "env-values-path"    = "clusters/${var.gcp_folder}/values"
      "env-overlay-path"   = "clusters/${var.gcp_folder}/overlays"
      "cluster-values-path" = "clusters/${var.gcp_folder}/${var.cluster_name}/values"
      "cluster-overlay-path" = "clusters/${var.gcp_folder}/${var.cluster_name}/overlays"
      
      # Sync wave adjustments by environment
      "argocd.argoproj.io/sync-wave-offset" = var.gcp_folder == "production" ? "100" : "0"
      
      # Resource profile indicator
      "argocd.argoproj.io/resource-profile" = var.gcp_folder == "production" ? "high" : "low"
      
      # Metadata tracking
      "argocd.argoproj.io/managed-by" = "terraform"
      "argocd.argoproj.io/created-at" = timestamp()
    }
  }
  
  data = {
    name   = var.cluster_name
    server = "https://kubernetes.default.svc"
    config = jsonencode({
      tlsClientConfig = {
        insecure = false
      }
    })
  }
}

# Wait for ArgoCD CRDs to be available
resource "time_sleep" "wait_for_argocd_crds" {
  depends_on = [helm_release.argocd]
  create_duration = "30s"
}

# Bootstrap application (always deploy for per-cluster model)
# Using null_resource + kubectl to avoid plan-time CRD validation issues
resource "null_resource" "bootstrap_application" {
  # Store values needed for destroy provisioner
  triggers = {
    namespace_name = var.namespace_name
    app_name      = "cluster-root"
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-bootstrap
  namespace: ${var.namespace_name}
  labels:
    app-type: bootstrap
    deployment-model: per-cluster
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  # Target only this specific cluster
  - clusters:
      selector:
        matchLabels:
          argocd.argoproj.io/secret-type: cluster
          cluster-name: ${var.cluster_name}
  template:
    metadata:
      name: cluster-root
      finalizers:
        - resources-finalizer.argocd.argoproj.io
      labels:
        app-type: bootstrap
        deployment-model: per-cluster
        cluster: '{{index .metadata.labels "cluster-name"}}'
        environment: '{{index .metadata.labels "environment"}}'
    spec:
      project: default
      source:
        repoURL: ${var.bootstrap_repo_url}
        # Use dynamic targetRevision from cluster metadata
        targetRevision: '{{index .metadata.labels "target-revision" | default "${var.bootstrap_repo_revision}"}}'
        path: bootstrap
      destination:
        server: '{{.server}}'
        namespace: ${var.namespace_name}
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
EOF
    EOT
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete applicationset ${self.triggers.app_name} -n ${self.triggers.namespace_name} --ignore-not-found=true"
  }
  
  depends_on = [
    helm_release.argocd,
    time_sleep.wait_for_argocd_crds
  ]
}

# GCP Service Accounts

# ArgoCD Server Service Account (always created for workload identity)
resource "google_service_account" "argocd_server" {
  account_id   = "${local.cluster_id}-argocd-server"
  display_name = "ArgoCD Server ${local.cluster_name}"
  description  = "Service account for ArgoCD server workload identity"
  project      = var.gcp_project_id
}

# ArgoCD Server IAM roles
resource "google_project_iam_member" "argocd_server_container_developer" {
  project = var.gcp_project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.argocd_server.email}"
}

# External DNS Service Account (for DNS management)
resource "google_service_account" "external_dns" {
  account_id   = "${local.cluster_id}-external-dns"
  display_name = "External DNS ${local.cluster_name}"
  description  = "Service account for External DNS DNS management"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "external_dns_admin" {
  project = var.gcp_project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

# Cert Manager Service Account (for Let's Encrypt DNS challenges)
resource "google_service_account" "cert_manager" {
  account_id   = "${local.cluster_id}-cert-manager"
  display_name = "Cert Manager ${local.cluster_name}"
  description  = "Service account for Cert Manager DNS challenges"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "cert_manager_dns_admin" {
  project = var.gcp_project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager.email}"
}

# External Secrets Service Account (for Google Secret Manager access)
resource "google_service_account" "external_secrets" {
  account_id   = "${local.cluster_id}-external-secrets"
  display_name = "External Secrets ${local.cluster_name}"
  description  = "Service account for External Secrets to access Google Secret Manager"
  project      = var.gcp_project_id
}

# Grant access to Secret Manager
resource "google_project_iam_member" "external_secrets_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.external_secrets.email}"
}

# OAuth Groups Service Account (optional)
resource "google_service_account" "oauth_groups_service_account" {
  count        = var.enable_oauth_groups_sa ? 1 : 0
  account_id   = "${local.cluster_id}-oauth-groups"
  display_name = "ArgoCD OAuth Groups ${local.cluster_name}"
  description  = "Service account for ArgoCD Groups API access"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "oauth_groups_directory_reader" {
  count   = var.enable_oauth_groups_sa ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/cloudidentity.groups.reader"
  member  = "serviceAccount:${google_service_account.oauth_groups_service_account[0].email}"
}

# Workload Identity bindings
resource "google_service_account_iam_member" "argocd_server_workload_identity" {
  service_account_id = google_service_account.argocd_server.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[${var.namespace_name}/argocd-server]"
}

resource "google_service_account_iam_member" "external_dns_workload_identity" {
  service_account_id = google_service_account.external_dns.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[external-dns/external-dns]"
}

resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  service_account_id = google_service_account.cert_manager.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[cert-manager/cert-manager]"
}

resource "google_service_account_iam_member" "external_secrets_workload_identity" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[external-secrets/external-secrets]"
}

resource "google_service_account_iam_member" "oauth_groups_workload_identity" {
  count              = var.enable_oauth_groups_sa ? 1 : 0
  service_account_id = google_service_account.oauth_groups_service_account[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[${var.namespace_name}/argocd-oauth]"
}


# Monitoring Service Account for Google Managed Prometheus
resource "google_service_account" "monitoring" {
  account_id   = "${local.cluster_id}-monitoring"
  display_name = "Monitoring ${local.cluster_name}"
  description  = "Service account for monitoring stack components (Grafana, Prometheus, etc.)"
  project      = var.gcp_project_id
}

# Monitoring viewer role
resource "google_project_iam_member" "monitoring_viewer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.monitoring.email}"
}

# Workload Identity bindings for Monitoring
resource "google_service_account_iam_member" "monitoring_workload_identity" {
  service_account_id = google_service_account.monitoring.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[monitoring/grafana]"
}


# Optional: OAuth token manager workload identity binding
# This is retained as it may be needed for future Grafana OAuth integration
resource "google_service_account_iam_member" "oauth_token_manager_workload_identity" {
  count              = var.enable_grafana_oauth_token_manager ? 1 : 0
  service_account_id = google_service_account.monitoring.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[monitoring/oauth-token-manager]"
}