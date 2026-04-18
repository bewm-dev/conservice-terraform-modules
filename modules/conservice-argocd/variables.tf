variable "cluster_name" {
  description = "EKS cluster name (used for naming and root app config)"
  type        = string
}

variable "github_org_url" {
  description = "GitHub organization URL for ArgoCD repo server"
  type        = string
}

variable "chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "9.5.0"
}

variable "namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "github_app_credentials" {
  description = <<-EOT
    GitHub App credentials used by ArgoCD to authenticate to private repos.
    Typically sourced from AWS Secrets Manager (e.g., github-apps/conservice-saas-gitops).
    Replaces the PAT-based github_token auth as of module v1.6.0.

    - app_id: numeric App ID (from App settings page)
    - installation_id: numeric Installation ID (from Install App URL)
    - private_key: PEM-encoded RSA private key (multi-line string)
  EOT
  type = object({
    app_id          = string
    installation_id = string
    private_key     = string
  })
  sensitive = true
}

variable "repo_url" {
  description = "Git repository URL for conservice-k8s-apps"
  type        = string
}

variable "additional_source_repos" {
  description = "Additional Git repo URLs allowed in the platform-addons AppProject (e.g., app repos)"
  type        = list(string)
  default     = []
}

variable "repo_target_revision" {
  description = "Git branch/tag to track for the root Application"
  type        = string
  default     = "main"
}

variable "enable_dex" {
  description = "Enable Dex OIDC config in Helm values. Secrets are created by ESO, not TF."
  type        = bool
  default     = true
}

variable "argocd_domain" {
  description = "ArgoCD server domain (e.g. argocd.conservice.cloud)"
  type        = string
}

variable "dex_admin_email" {
  description = "Google Workspace admin email for Dex directory API"
  type        = string
  default     = ""
}

variable "dex_hosted_domain" {
  description = "Google Workspace domain for Dex SSO"
  type        = string
  default     = ""
}

variable "bootstrap_cluster_path" {
  description = "Path in repo for this cluster's app-of-apps chart (e.g. clusters/plat-use1-mgmt)"
  type        = string
}
