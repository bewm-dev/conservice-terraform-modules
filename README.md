# Conservice Terraform Modules

Shared Terraform modules for the Conservice AWS greenfield platform.

## Naming Convention

All resources use the prefix `conservice-{env}-{resource}`. No exceptions.

## Modules

| Module | Purpose | Status |
|--------|---------|--------|
| `aws-vpc` | VPC with public/private/database subnets, NAT, flow logs | Done |
| `aws-eks` | EKS cluster with Karpenter support, Pod Identity | Planned |
| `aws-aurora` | Aurora PostgreSQL Serverless v2 (platform-level) | Planned |
| `aurora-database` | App-level database, roles, grants with IAM auth (guardrail) | Done |
| `tgw-spoke-attachment` | TGW attachment + routes for spoke VPCs | Planned |
| `sqs-queue` | App-level SQS with DLQ, encryption, tags (guardrail) | Planned |
| `sns-topic` | App-level SNS with encryption, tags (guardrail) | Planned |
| `s3-bucket` | App-level S3 with encryption, versioning, tags (guardrail) | Planned |

## Usage

```hcl
module "vpc" {
  source = "git::https://github.com/shawnpetersen/conservice-terraform-modules.git//modules/aws-vpc?ref=v1.0.0"

  env     = "dev"
  project = "conservice"
  vpc_cidr = "10.244.0.0/16"
  azs      = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```

## Versioning

Use git tags for version pinning: `?ref=v1.0.0`. Never reference `?ref=main` in production.
