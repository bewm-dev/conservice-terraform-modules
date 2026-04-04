# -----------------------------------------------------------------------------
# ArgoCD Installation and Bootstrap
# -----------------------------------------------------------------------------
#
# Installs ArgoCD via Helm and creates the bootstrap root Application that
# points to the app-of-apps chart in conservice-k8s-apps. ArgoCD then
# self-manages from Git going forward.
#
# IAM (Pod Identity) is created externally in eks-mgmt/main.tf alongside
# other addon roles — this module only consumes the role ARN.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Google Service Account Secret (for Dex group lookup)
# -----------------------------------------------------------------------------
#
# Dex needs a Google service account JSON key to query the Admin Directory API
# for group memberships. This secret is mounted into the Dex pod as a file.
# Only created when Dex is enabled.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret" "dex_google_sa" {
  count = var.enable_dex ? 1 : 0

  metadata {
    name      = "dex-google-groups"
    namespace = var.namespace
  }

  data = {
    "googleAuth.json" = var.google_sa_json
  }

  depends_on = [kubernetes_namespace.argocd]
}

# -----------------------------------------------------------------------------
# ArgoCD Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = false
  wait             = true
  timeout          = 600

  values = [templatefile("${path.module}/argocd-values.yaml.tftpl", {
    argocd_url           = var.argocd_url
    enable_dex           = var.enable_dex
    google_client_id     = var.google_oidc_client_id
    google_client_secret = var.google_oidc_client_secret
    google_admin_email   = var.google_admin_email
    github_token         = var.github_token
  })]

  depends_on = [kubernetes_namespace.argocd, kubernetes_secret.dex_google_sa]
}

# -----------------------------------------------------------------------------
# AppProject: platform-addons
# -----------------------------------------------------------------------------
#
# Restricts platform addon apps to specific source repos and namespaces.
# Apps are NOT placed in the default project.
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "project_platform_addons" {
  depends_on = [helm_release.argocd]

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "platform-addons"
      namespace = var.namespace
    }
    spec = {
      description = "Platform infrastructure addons managed by app-of-apps"
      sourceRepos = [
        var.repo_url,
      ]
      destinations = [
        {
          namespace = "*"
          server    = "*"
        },
      ]
      clusterResourceWhitelist = [
        {
          group = "*"
          kind  = "*"
        },
      ]
      orphanedResources = {
        warn = true
      }
    }
  })
}

# -----------------------------------------------------------------------------
# Bootstrap Root Application
# -----------------------------------------------------------------------------
#
# Points to clusters/{cluster}/ in conservice-k8s-apps. This Helm chart
# generates child Application CRs (one per addon) via the app-of-apps pattern.
# ArgoCD then syncs each child independently with sync-wave ordering.
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "root_application" {
  depends_on = [helm_release.argocd, kubectl_manifest.project_platform_addons]

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "${var.cluster_name}--root"
      namespace = var.namespace
      annotations = {
        "argocd.argoproj.io/compare-options" = "ServerSideDiff=true"
      }
    }
    spec = {
      project = "platform-addons"
      source = {
        repoURL        = var.repo_url
        targetRevision = var.repo_target_revision
        path           = var.bootstrap_cluster_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.namespace
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
