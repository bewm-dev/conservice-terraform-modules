# -----------------------------------------------------------------------------
# Register Workload Cluster with ArgoCD (bearer token auth)
# -----------------------------------------------------------------------------
#
# Dual-provider pattern: the workload cluster registers ITSELF with ArgoCD.
#
# - `kubernetes` (default) targets the WORKLOAD cluster:
#   Creates ServiceAccount + ClusterRole + bearer token for ArgoCD to use.
#
# - `kubernetes.mgmt` targets the MANAGEMENT cluster:
#   Creates the cluster secret + root Application in ArgoCD's namespace.
#
# No IAM role chaining needed — ArgoCD authenticates to the workload cluster
# using the bearer token stored in the cluster secret.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Workload Cluster: ServiceAccount + RBAC for ArgoCD
# (created on the workload cluster via default kubernetes provider)
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "argocd_manager" {
  metadata {
    name      = "argocd-manager"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "argocd"
    }
  }
}

resource "kubernetes_secret" "argocd_manager_token" {
  metadata {
    name      = "argocd-manager-token"
    namespace = "kube-system"
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account.argocd_manager.metadata[0].name
      "kubernetes.io/service-account.namespace" = "kube-system"
    }
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "argocd"
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true

  depends_on = [kubernetes_service_account.argocd_manager]
}

resource "kubernetes_cluster_role" "argocd_manager" {
  metadata {
    name = "argocd-manager-role"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "argocd"
    }
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  rule {
    non_resource_urls = ["*"]
    verbs             = ["*"]
  }
}

resource "kubernetes_cluster_role_binding" "argocd_manager" {
  metadata {
    name = "argocd-manager-role-binding"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "argocd"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.argocd_manager.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.argocd_manager.metadata[0].name
    namespace = "kube-system"
  }
}

# -----------------------------------------------------------------------------
# Management Cluster: ArgoCD Cluster Secret
# (created on the mgmt cluster via kubernetes.mgmt provider)
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "cluster" {
  provider = kubernetes.mgmt

  metadata {
    name      = "${var.cluster_name}-secret"
    namespace = var.argocd_namespace

    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "app.kubernetes.io/managed-by"   = "terraform"
    }
  }

  data = {
    name   = var.cluster_name
    server = var.cluster_endpoint
    config = jsonencode({
      bearerToken = kubernetes_secret.argocd_manager_token.data["token"]
      tlsClientConfig = {
        insecure = false
        caData   = base64encode(kubernetes_secret.argocd_manager_token.data["ca.crt"])
      }
    })
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# Management Cluster: Bootstrap Root Application
# (created on the mgmt cluster via kubectl.mgmt provider)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "root_application" {
  provider   = kubectl.mgmt
  depends_on = [kubernetes_secret.cluster]

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "${var.cluster_name}--root"
      namespace = var.argocd_namespace
      annotations = {
        "argocd.argoproj.io/compare-options" = "ServerSideDiff=true"
      }
    }
    spec = {
      project = var.project
      source = {
        repoURL        = var.repo_url
        targetRevision = var.repo_target_revision
        path           = var.bootstrap_cluster_path
      }
      destination = {
        # Root app creates child Application CRDs — these live on the
        # management cluster where ArgoCD runs, not on the workload cluster.
        server    = "https://kubernetes.default.svc"
        namespace = var.argocd_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
        ]
        retry = {
          limit = 3
          backoff = {
            duration    = "5s"
            factor      = 2
            maxDuration = "2m"
          }
        }
      }
    }
  })
}
