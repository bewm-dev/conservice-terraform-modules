output "cluster_secret_name" {
  description = "Name of the ArgoCD cluster secret on the management cluster"
  value       = kubernetes_secret.cluster.metadata[0].name
}

output "root_app_name" {
  description = "Name of the root Application for this cluster"
  value       = "${var.cluster_name}--root"
}
