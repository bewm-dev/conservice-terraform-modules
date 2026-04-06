# -----------------------------------------------------------------------------
# Register Remote EKS Cluster with ArgoCD
# -----------------------------------------------------------------------------
#
# Creates a cluster secret on the ArgoCD management cluster using IAM role
# auth (awsAuthConfig). No ServiceAccount tokens or ClusterRoles needed on
# the remote cluster — IAM role + EKS access entry handles everything.
#
# Provider note: The kubernetes and kubectl providers used by this module
# must be configured to target the MANAGEMENT cluster (where ArgoCD runs),
# not the remote cluster being registered.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ArgoCD Cluster Secret (on management cluster)
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "cluster" {
  metadata {
    name      = var.cluster_secret_name
    namespace = var.argocd_namespace

    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }

  data = {
    name   = var.cluster_name
    server = var.cluster_endpoint
    config = jsonencode(merge(
      {
        awsAuthConfig = {
          clusterName = var.cluster_name
          roleARN     = var.argocd_role_arn
        }
      },
      var.cluster_ca_data != "" ? {
        tlsClientConfig = {
          caData = var.cluster_ca_data
        }
      } : {}
    ))
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# Bootstrap Root Application (for this remote cluster)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "root_application" {
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
        server    = var.cluster_endpoint
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
