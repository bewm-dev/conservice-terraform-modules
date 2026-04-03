output "namespace" {
  description = "Kubernetes namespace where ArgoCD is installed"
  value       = helm_release.argocd.namespace
}

output "chart_version" {
  description = "Installed ArgoCD Helm chart version"
  value       = helm_release.argocd.version
}

output "root_app_name" {
  description = "Name of the bootstrap root Application"
  value       = "${var.cluster_name}--root"
}
