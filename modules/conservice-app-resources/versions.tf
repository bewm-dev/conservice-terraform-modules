terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.ecr]
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.21"
    }
    temporalcloud = {
      source  = "temporalio/temporalcloud"
      version = "~> 1.3"
    }
  }
}
