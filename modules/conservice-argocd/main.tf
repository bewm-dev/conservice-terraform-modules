# -----------------------------------------------------------------------------
# ArgoCD Bootstrap
# -----------------------------------------------------------------------------
#
# Minimal ArgoCD install — just enough to connect to the Git repo and sync
# the app-of-apps. ArgoCD self-manages from Git after the root Application
# syncs, which provides the full config (Dex SSO, domain, RBAC, etc.)
#
# IAM (Pod Identity) is created externally in eks-mgmt/main.tf.
# Dex SSO, Gateway API, and all addon config comes from the k8s-apps repo.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ArgoCD Helm Release (bootstrap only)
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = true
  wait             = true
  timeout          = 600

  values = [templatefile("${path.module}/argocd-values.yaml.tftpl", {
    github_token   = var.github_token
    github_org_url = var.github_org_url
    enable_dex     = var.enable_dex
  })]

  # After bootstrap, ArgoCD self-manages from Git.
  # Ignore values so Terraform doesn't fight ArgoCD for control.
  lifecycle {
    ignore_changes = [values]
  }
}

# -----------------------------------------------------------------------------
# AppProject: platform-addons
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
      # Orphan monitoring disabled — the argocd namespace contains resources
      # not owned by the self-manage app (ESO-synced secrets, Application CRs
      # from root app). These are expected and not true orphans.
    }
  })
}

# -----------------------------------------------------------------------------
# Bootstrap Root Application
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
