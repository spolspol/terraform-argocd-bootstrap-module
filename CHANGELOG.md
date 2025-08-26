# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-08-25

### Added
- Initial release of the Terraform ArgoCD Bootstrap Module
- Minimal bootstrap approach for ArgoCD deployment
- Workload Identity integration for GCP services
- Support for private GitHub repositories
- Comprehensive cluster metadata for ApplicationSets
- Service account creation for:
  - ArgoCD Server
  - External DNS
  - Cert Manager
  - External Secrets
  - Monitoring (Grafana/Prometheus)
  - OAuth Groups (optional)
- Bootstrap ApplicationSet for cluster self-management
- Multi-environment support (development, staging, production)
- Ingress configuration support
- External Secrets management integration
- Comprehensive examples and documentation

### Features
- GitOps-first design philosophy
- Dynamic cluster metadata configuration
- Automatic Workload Identity bindings
- Support for ArgoCD Helm chart version 8.1.3+
- OAuth token manager support for Grafana
- Configurable bootstrap repository revision
- Rich output variables for integration

### Documentation
- Architecture documentation
- Bootstrap hierarchy guide
- Configuration metadata architecture
- External secrets management guide
- Multiple usage examples
- Troubleshooting guide
- Migration instructions