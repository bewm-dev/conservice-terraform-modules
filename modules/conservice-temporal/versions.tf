terraform {
  required_version = "~> 1.14"

  required_providers {
    temporalcloud = {
      source  = "temporalio/temporalcloud"
      version = "~> 1.3"
    }
  }
}
