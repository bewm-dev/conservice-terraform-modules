# -----------------------------------------------------------------------------
# ArgoCD Bootstrap
# -----------------------------------------------------------------------------
#
# Installs ArgoCD via Helm with Dex SSO config. Dex secrets are NOT created
# here — ESO creates them from Secrets Manager after ArgoCD is running.
# Dex will fail initially; Reloader restarts pods when secrets appear.
#
# Bootstrap sequence:
#   1. TF creates namespace + Helm install (Dex config refs secret names)
#   2. Root Application syncs → ESO deploys (wave 1)
#   3. ESO creates argocd-dex-secrets + dex-google-groups from Secrets Manager
#   4. Reloader detects new secrets, restarts ArgoCD → Dex SSO works
#
# IAM (Pod Identity) is created externally in eks-mgmt/main.tf.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
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
  wait    = false
  timeout = 600

  values = [templatefile("${path.module}/argocd-values.yaml.tftpl", {
    github_token      = var.github_token
    github_org_url    = var.github_org_url
    enable_dex        = var.enable_dex
    argocd_domain     = var.argocd_domain
    dex_admin_email   = var.dex_admin_email
    dex_hosted_domain = var.dex_hosted_domain
  })]

  depends_on = [kubernetes_namespace.argocd]

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
  depends_on        = [helm_release.argocd]
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "platform-addons"
      namespace = var.namespace
    }
    spec = {
      description = "Platform infrastructure addons managed by app-of-apps"
      sourceRepos = concat([var.repo_url], var.additional_source_repos)
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
