# Conservice Terraform Modules

Shared Terraform modules for the Conservice AWS greenfield platform.

## Naming Convention

All resources use the prefix `conservice-{env}-{resource}`. No exceptions.

## Modules

### Platform Modules (SRE-owned)

| Module | Purpose | Status |
|--------|---------|--------|
| `aws-vpc` | VPC with public/private/database subnets, NAT, flow logs | Done |
| `aws-eks` | EKS workload cluster with Pod Identity, OIDC | Done |
| `aws-eks-cluster` | EKS management cluster with admin access entries | Done |
| `aws-aurora` | Aurora PostgreSQL Serverless v2 with presets (lean/single/HA) | Done |
| `tgw-spoke-attachment` | TGW attachment + routes for spoke VPCs | Planned |

### App-Level Modules (dev team-facing via YAML config)

| Module | Purpose | Status |
|--------|---------|--------|
| `app-infra` | Root module that reads YAML config and provisions all app resources | Done |
| `aurora-database` | PostgreSQL database, IAM-auth roles, grants (guardrail) | Done |

The `app-infra` module provisions S3, SQS, SNS, and databases from YAML config files. Dev teams never write Terraform — they edit YAML in their app repo's `infra/` directory.

## App-Level Config Pattern

Adopted from Cybertron's 3-layer config merge:

```
my-app/
├── src/
├── deploy/              # Kustomize overlays (ArgoCD)
└── infra/
    ├── base.yaml        # Team, domain, portfolio (shared across envs)
    ├── database.yaml    # Database defaults (all envs)
    ├── s3.yaml          # S3 bucket defaults (all envs)
    ├── sqs.yaml         # SQS queue defaults (all envs)
    └── envs/
        ├── dev.yaml     # Dev overrides only
        ├── staging.yaml
        └── prod.yaml
```

See `examples/app-infra-config/` for a complete example.

## Usage

### Platform module (in conservice-aws-platform)

```hcl
module "vpc" {
  source = "git::https://github.com/shawnpetersen/conservice-terraform-modules.git//modules/aws-vpc?ref=aws-vpc/v1.0.0"

  env      = "dev"
  project  = "conservice"
  vpc_cidr = "10.244.0.0/16"
  azs      = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```

### App-level infra (in app repo CI)

```hcl
module "infra" {
  source = "git::https://github.com/shawnpetersen/conservice-terraform-modules.git//modules/app-infra?ref=app-infra/v1.0.0"

  app_name    = "my-billing-service"
  env         = "dev"
  config_path = "${path.root}/infra"
}
```

## Versioning

Use directory-scoped git tags: `?ref=aws-vpc/v1.0.0`. Never reference `?ref=main` in production.
