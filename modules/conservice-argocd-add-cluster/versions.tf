terraform {
  required_version = "~> 1.14"

  required_providers {
    kubernetes = {
      source                = "hashicorp/kubernetes"
      version               = "~> 2.38.0"
      configuration_aliases = [kubernetes, kubernetes.mgmt]
    }
    kubectl = {
      source                = "alekc/kubectl"
      version               = "~> 2.1.0"
      configuration_aliases = [kubectl.mgmt]
    }
  }
}
