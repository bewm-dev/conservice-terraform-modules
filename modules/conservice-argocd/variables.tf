variable "cluster_name" {
  description = "EKS cluster name (used for naming and root app config)"
  type        = string
}

variable "chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "9.4.17"
}

variable "namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_url" {
  description = "ArgoCD external URL (e.g. https://argocd.conservice.ai)"
  type        = string
}

variable "github_token" {
  description = "GitHub PAT for repo access (from Secrets Manager via ephemeral)"
  type        = string
  ephemeral   = true
  sensitive   = true
}

variable "google_oidc_client_id" {
  description = "Google OAuth client ID for Dex SSO (from Secrets Manager via ephemeral)"
  type        = string
  ephemeral   = true
  sensitive   = true
  default     = ""
}

variable "google_oidc_client_secret" {
  description = "Google OAuth client secret for Dex SSO (from Secrets Manager via ephemeral)"
  type        = string
  ephemeral   = true
  sensitive   = true
  default     = ""
}

variable "enable_dex" {
  description = "Enable Dex SSO (requires Google OAuth credentials)"
  type        = bool
  default     = false
}

variable "repo_url" {
  description = "Git repository URL for conservice-k8s-apps"
  type        = string
  default     = "https://github.com/shawnpetersen/conservice-k8s-apps.git"
}

variable "repo_target_revision" {
  description = "Git branch/tag to track for the root Application"
  type        = string
  default     = "main"
}

variable "bootstrap_cluster_path" {
  description = "Path in repo for this cluster's app-of-apps chart (e.g. clusters/platform-mgmt)"
  type        = string
}
