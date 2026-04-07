output "cluster_secret_name" {
  description = "Name of the ArgoCD cluster secret on the management cluster"
  value       = kubernetes_secret.cluster.metadata[0].name
}

output "root_app_name" {
  description = "Name of the root Application for this cluster"
  value       = "${var.cluster_name}--root"
}

output "argocd_manager_sa" {
  description = "Name of the ArgoCD manager ServiceAccount on the workload cluster"
  value       = kubernetes_service_account.argocd_manager.metadata[0].name
}
