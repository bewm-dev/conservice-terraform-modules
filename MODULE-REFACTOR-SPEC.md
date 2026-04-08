# Module Refactor Spec

Status: App-level modules refactored, all modules use `conservice-` prefix (Apr 5, 2026)

## Context

The `conservice-aws-platform` account configs originally used custom wrapper modules for VPC, EKS, and Aurora. These were replaced by community `terraform-aws-modules/*` during the full community module adoption (commit `3b247fc`). Custom modules are retained only where community modules don't cover our patterns.

App-level modules (`app-infra`, `aurora-database`) were refactored to `conservice-app-resources` and `conservice-app-database` for naming consistency and to use community S3 module internally.

## History

### Deleted (superseded by community modules)

- `aws-vpc` → `terraform-aws-modules/vpc/aws` + vpc-endpoints submodule
- `aws-eks-cluster` → `terraform-aws-modules/eks/aws`
- `aws-aurora` → `terraform-aws-modules/rds-aurora/aws`
- `conservice-eks-cluster` → never adopted in account configs
- `conservice-vpc-network` → account configs use community VPC + inline SGs

### Renamed (app-level modules)

- `app-infra` → `conservice-app-resources` (also switched S3 to community module, added greenfield naming)
- `aurora-database` → `conservice-app-database`

## Current Modules

### Platform (SRE-owned, used in conservice-aws-platform)

| Module | Purpose |
|--------|---------|
| `conservice-account-iam-baseline` | Per-account baseline IAM (TF execution, ECR pull, Aurora access) |
| `conservice-eks-pod-identity` | Pod Identity roles for LBC, ExternalDNS, ESO, Container Insights, Kargo |
| `conservice-argocd` | ArgoCD bootstrap via Helm + Dex SSO secrets |
| `conservice-argocd-add-cluster` | Register remote EKS cluster with ArgoCD |
| `conservice-vpn-peer` | Site-to-site VPN on Transit Gateway |

### App-Level (dev team-facing, used in app repos)

| Module | Purpose |
|--------|---------|
| `conservice-app-resources` | Orchestrator — reads YAML config, provisions S3/SQS/SNS/databases |
| `conservice-app-database` | PostgreSQL database + IAM-auth roles inside shared Aurora cluster |
