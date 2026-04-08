terraform {
  required_version = "~> 1.14"
  backend "s3" { use_lockfile = true }

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    postgresql = { source = "cyrilgdn/postgresql", version = "~> 1.21" }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Env       = var.env
      Project   = "conservice"
      TFPath    = "apps/my-app"
      ManagedBy = "terraform"
    }
  }
}

provider "postgresql" {
  host     = var.aurora_host
  port     = 5432
  username = var.aurora_master_username
  password = var.aurora_master_password
  sslmode  = "require"
}
