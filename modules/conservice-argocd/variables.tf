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
  default     = "9.4.2"
}

variable "namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "github_token" {
  description = "GitHub PAT for repo access. Sensitive — stored in Helm values in state (encrypted)."
  type        = string
  sensitive   = true
}

variable "repo_url" {
  description = "Git repository URL for conservice-k8s-apps"
  type        = string
}

variable "repo_target_revision" {
  description = "Git branch/tag to track for the root Application"
  type        = string
  default     = "main"
}

variable "enable_dex" {
  description = "Enable Dex OIDC for Google SSO login"
  type        = bool
  default     = true
}

variable "dex_google_client_id" {
  description = "Google OAuth client ID for Dex SSO"
  type        = string
  default     = ""
  sensitive   = true
}

variable "dex_google_client_secret" {
  description = "Google OAuth client secret for Dex SSO"
  type        = string
  default     = ""
  sensitive   = true
}

variable "dex_google_sa_json" {
  description = "Google service account JSON for Dex directory API group lookup"
  type        = string
  default     = ""
  sensitive   = true
}

variable "argocd_domain" {
  description = "ArgoCD server domain (e.g. argocd.conservice.cloud)"
  type        = string
  default     = ""
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
