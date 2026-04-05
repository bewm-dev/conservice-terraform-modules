# Conservice Terraform Modules

Shared Terraform modules for the Conservice AWS greenfield platform.

## Modules

### Platform Modules (SRE-owned)

Used by `conservice-aws-platform` account configs. These cover patterns that community modules don't handle.

| Module | Purpose | Used By |
|--------|---------|---------|
| `conservice-account-base` | Per-account baseline IAM (TF execution, ECR pull, Aurora access roles) | All account `global/iam` |
| `conservice-eks-addons` | Pod Identity roles for LBC, ExternalDNS, ESO, Karpenter, Container Insights | All EKS cluster configs |
| `conservice-argocd` | ArgoCD bootstrap via Helm (minimal install + Dex SSO secrets) | Platform eks-mgmt |
| `conservice-argocd-add-cluster` | Register remote EKS cluster with ArgoCD management cluster | Production (Phase 7.3) |
| `conservice-vpn-peer` | Site-to-site VPN peer on Transit Gateway with ephemeral PSKs | Platform network |

### App-Level Modules (dev team-facing via YAML config)

| Module | Purpose |
|--------|---------|
| `app-infra` | Root module — reads YAML config and provisions S3, SQS, SNS, databases |
| `aurora-database` | PostgreSQL database + IAM-auth roles + grants inside shared Aurora cluster |

Dev teams edit YAML in their app repo's `infra/` directory. The `app-infra` module + CI handles the rest.

### Community Modules (used directly in account configs)

Complex infrastructure components use [terraform-aws-modules](https://github.com/terraform-aws-modules) from the Terraform Registry. See `APPLY-ORDER.md` in `claude-code-conservice` for the full list.

| Module | Used For |
|--------|----------|
| `terraform-aws-modules/vpc/aws` | All VPCs + VPC endpoints |
| `terraform-aws-modules/transit-gateway/aws` | Platform TGW hub |
| `terraform-aws-modules/eks/aws` | All EKS clusters + Karpenter submodule |
| `terraform-aws-modules/rds-aurora/aws` | All Aurora clusters |
| `terraform-aws-modules/acm/aws` | Platform ACM certs |
| `terraform-aws-modules/route53/aws` | Platform Route53 zones |
| `terraform-aws-modules/s3-bucket/aws` | Log archive S3 buckets |
| `terraform-aws-modules/iam/aws` | GitHub OIDC provider + role |

## App-Level Config Pattern

3-layer YAML config merge (base → resource defaults → env overrides):

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
module "account_base" {
  source = "git::https://github.com/shawnpetersen/conservice-terraform-modules.git//modules/conservice-account-base?ref=conservice-account-base/v1.0.0"

  env              = "dev"
  aws_account_id   = "106751264134"
  tools_account_id = "626209130023"
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

Use directory-scoped git tags: `?ref=conservice-account-base/v1.0.0`. Never reference `?ref=main` in production.
