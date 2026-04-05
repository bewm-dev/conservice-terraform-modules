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
  default     = "9.4.17"
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

variable "bootstrap_cluster_path" {
  description = "Path in repo for this cluster's app-of-apps chart (e.g. clusters/plat-use1-mgmt)"
  type        = string
}
