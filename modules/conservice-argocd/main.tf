# -----------------------------------------------------------------------------
# ArgoCD Bootstrap
# -----------------------------------------------------------------------------
#
# Full ArgoCD install with Dex SSO config. Bootstrap secrets are created
# before the Helm release so Dex pods can mount them on first start.
# ArgoCD self-manages from Git after the root Application syncs.
#
# IAM (Pod Identity) is created externally in eks-mgmt/main.tf.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Namespace + Bootstrap Secrets (BEFORE Helm install)
# Dex pods mount these as volumes — they must exist before ArgoCD starts.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret" "dex_oidc" {
  count = var.enable_dex ? 1 : 0

  metadata {
    name      = "argocd-dex-secrets"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/part-of" = "argocd"
    }
  }

  data = {
    "dex.google.clientID"     = var.dex_google_client_id
    "dex.google.clientSecret" = var.dex_google_client_secret
  }

  type       = "Opaque"
  depends_on = [kubernetes_namespace.argocd]

  lifecycle {
    ignore_changes = [data, metadata[0].annotations, metadata[0].labels]
  }
}

resource "kubernetes_secret" "dex_google_groups" {
  count = var.enable_dex ? 1 : 0

  metadata {
    name      = "dex-google-groups"
    namespace = var.namespace
    labels    = {}
  }

  data = {
    "googleAuth.json" = var.dex_google_sa_json
  }

  type       = "Opaque"
  depends_on = [kubernetes_namespace.argocd]

  lifecycle {
    ignore_changes = [data, metadata[0].annotations, metadata[0].labels]
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
  wait             = true
  timeout          = 600

  values = [templatefile("${path.module}/argocd-values.yaml.tftpl", {
    github_token      = var.github_token
    github_org_url    = var.github_org_url
    enable_dex        = var.enable_dex
    argocd_domain     = var.argocd_domain
    dex_admin_email   = var.dex_admin_email
    dex_hosted_domain = var.dex_hosted_domain
  })]

  depends_on = [
    kubernetes_namespace.argocd,
    kubernetes_secret.dex_oidc,
    kubernetes_secret.dex_google_groups,
  ]

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
