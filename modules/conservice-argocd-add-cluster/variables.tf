variable "cluster_name" {
  description = "Remote EKS cluster name to register with ArgoCD"
  type        = string
}

variable "cluster_secret_name" {
  description = "Short name for the ArgoCD cluster secret (e.g. prod-workload)"
  type        = string
}

variable "cluster_endpoint" {
  description = "Remote EKS cluster API server endpoint"
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed on the management cluster"
  type        = string
  default     = "argocd"
}

variable "argocd_role_arn" {
  description = "IAM role ARN that ArgoCD assumes for cross-account cluster access"
  type        = string
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
  description = "Path in repo for this cluster's app-of-apps chart (e.g. clusters/prod-workload)"
  type        = string
}

variable "project" {
  description = "ArgoCD AppProject name for apps deployed to this cluster"
  type        = string
  default     = "platform-addons"
}
