terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      # No aliases needed — all resources are in the workload account.
      # ECR repos are in the platform account's TF, SSO in the org account's TF.
    }
    # postgresql and temporalcloud are declared in their respective sub-modules
    # (conservice-app-database, conservice-temporal) and inherited via provider
    # pass-through. This avoids forcing every root module to configure providers
    # for features it doesn't use.
  }
}
