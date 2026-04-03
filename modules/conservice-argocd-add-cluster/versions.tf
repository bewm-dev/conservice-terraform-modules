terraform {
  required_version = "~> 1.14"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1.0"
    }
  }
}
