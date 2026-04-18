variable "cluster_name" {
  description = "Workload EKS cluster name (used for secret naming and ArgoCD display)"
  type        = string
}

variable "cluster_endpoint" {
  description = "Workload EKS cluster API server endpoint"
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed on the management cluster"
  type        = string
  default     = "argocd"
}

variable "repo_url" {
  description = "Git repository URL for conservice-argocd-apps"
  type        = string
}

variable "repo_target_revision" {
  description = "Git branch/tag to track for the root Application"
  type        = string
  default     = "main"
}

variable "bootstrap_cluster_path" {
  description = "Path in repo for this cluster's app-of-apps chart (e.g. clusters/stg-use1-workload)"
  type        = string
}

variable "project" {
  description = "ArgoCD AppProject name for apps deployed to this cluster"
  type        = string
  default     = "platform-addons"
}
