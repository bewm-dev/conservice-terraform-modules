# Module Refactor Spec

Status: Modules complete, account config refactor next (Apr 1, 2026)

## Context

The `conservice-aws-platform` account configs have ~1,900 lines of duplicated code across tools/dev/staging/prod. The same IAM roles, security groups, Pod Identity policies, and Karpenter configs are copy-pasted with minor variable substitutions.

We're refactoring into **capability-based modules** that group resources by platform function, not AWS service. Each module is self-contained — you get everything needed for that capability in one module call.

## Completed

- [x] Merged `aws-eks` + `aws-eks-cluster` into single `aws-eks-cluster` module (parameterized access type)
- [x] Built `conservice-account-base` module — per-account baseline IAM (TF execution, EKS, ECR, Aurora roles)
- [x] Built `conservice-vpc-network` module — spoke VPC + SGs + TGW connectivity
- [x] Built `conservice-eks-cluster` module — KMS + EKS cluster wrapper
- [x] Built `conservice-eks-addons` module — Pod Identity roles for LBC, ExternalDNS, ESO, Karpenter + SQS/EventBridge

## Next: Account Config Refactor

Replace the ~1,900 lines of duplicated code in account configs with thin module calls (see "After Modules" section below).

## Module Reference

### 1. `conservice-account-base` module

**Creates**: Per-account baseline IAM that every account needs.

**Resources**:
- TF execution role (cross-account from tools, or self-contained for tools account)
  - Variable: `role_type` = "cross-account" | "self-contained"
  - Cross-account trusts tools account root with external ID
  - Self-contained trusts own account root with ci-terraform tag
- TF execution policy (ec2, eks, rds, s3, iam, kms, secretsmanager, elb, autoscaling, cloudwatch, logs, route53, acm, sqs, sns, ssm + state bucket + DynamoDB lock)
- EKS cluster role (eks.amazonaws.com trust)
- EKS node role + instance profile (ec2.amazonaws.com trust, 4 managed policies)
- ECR cross-account pull role + policy (workload accounts only)
- Aurora access role + policy (rds.amazonaws.com trust, S3 + CloudWatch)

**Inputs**:
- `env` (string) — dev, staging, prod, tools
- `aws_account_id` (string)
- `tools_account_id` (string, optional) — for cross-account trust
- `enable_aurora_role` (bool, default true) — tools doesn't need this
- `enable_ecr_pull_role` (bool, default true) — tools doesn't need this

**Outputs**:
- `tf_execution_role_arn`
- `eks_cluster_role_arn`
- `eks_node_role_arn`
- `eks_node_instance_profile_name`
- `ecr_cross_account_pull_role_arn`
- `aurora_access_role_arn`

**Source**: Extract from `accounts/dev/global/iam/main.tf` (representative of all accounts)

### 2. `conservice-vpc-network` module

**Creates**: Complete networking for an account — VPC + security groups + TGW connectivity.

**Resources**:
- VPC (via existing `aws-vpc` module call)
- EKS cluster additional security group (HTTPS from VPC + cross-VPC)
- Aurora security group (PostgreSQL 5432 from VPC)
- Internal security group (all traffic from VPC + 10.0.0.0/8)
- Transit Gateway attachment (to existing TGW in tools account)
- TGW routes on private app + private DB route tables (10.0.0.0/8, 172.16.0.0/12)

**Inputs**:
- `env`, `aws_region`, `project`
- `vpc_cidr` (string)
- `azs` (list)
- `transit_gateway_id` (string, optional — null for tools hub which creates its own TGW)
- `single_nat_gateway` (bool, default true)
- `enable_flow_logs` (bool, default true)
- `flow_log_retention` (number, default 30)
- `enable_vpc_endpoints` (bool, default true)
- `interface_vpc_endpoints` (list, default ["ecr.api", "ecr.dkr", "sts", "secretsmanager", "logs"])
- `create_eks_sg` (bool, default true)
- `create_aurora_sg` (bool, default true)

**Outputs**:
- All VPC outputs (vpc_id, subnet_ids, etc.)
- `eks_cluster_additional_sg_id`
- `aurora_sg_id`
- `internal_sg_id`
- `tgw_attachment_id`

**Note**: The tools account VPC is special — it creates the Transit Gateway itself. The module wraps spoke VPCs. Tools VPC stays as custom config (creates TGW, prefix lists, cross-region peering).

### 3. `conservice-eks-cluster` module

**Creates**: Complete EKS cluster with all IAM plumbing.

**Resources**:
- KMS key for EKS secrets encryption
- EKS cluster (via existing `aws-eks` module)

**Inputs**:
- `cluster_name` (string)
- `env`, `project`
- `vpc_id`, `subnet_ids`
- `cluster_role_arn` (from account-base)
- `node_role_arn` (from account-base, optional)
- `cluster_admin_arns` (list, optional)
- `additional_security_group_ids` (list, optional)
- `cluster_version` (string, default "1.33")
- `kms_deletion_window` (number, default 30)

**Outputs**:
- `cluster_name`, `cluster_endpoint`, `cluster_arn`
- `cluster_certificate_authority`
- `cluster_security_group_id`
- `oidc_provider_arn`, `oidc_provider_url`
- `kms_key_arn`, `kms_key_id`

### 4. `conservice-eks-addons` module

**Creates**: All Pod Identity roles + supporting infra for EKS platform addons.

**Resources per addon**:
- IAM role (eks-pods.amazonaws.com trust)
- IAM policy (scoped per addon)
- EKS Pod Identity association

**Addons**:
- `aws_load_balancer_controller` — EC2/ELB/ACM/Route53 permissions (scoped, not `*`)
- `external_dns` — Route53 permissions (scoped to specific hosted zone IDs)
- `external_secrets` — Secrets Manager + SSM read
- `karpenter` — EC2 provisioning + pricing + SQS interruption queue + 3 EventBridge rules

**Inputs**:
- `cluster_name`, `cluster_arn` (string)
- `env`, `aws_account_id`
- `node_role_arn` (for Karpenter iam:PassRole)
- `enable_lbc` (bool, default true)
- `enable_external_dns` (bool, default true)
- `enable_eso` (bool, default true)
- `enable_karpenter` (bool, default true)
- `route53_zone_ids` (list, optional — for scoping ExternalDNS)

**Outputs**:
- `lbc_role_arn`
- `external_dns_role_arn`
- `eso_role_arn`
- `karpenter_role_arn`
- `karpenter_queue_name`

**IAM scoping improvements over current code**:
- LBC: `iam:CreateServiceLinkedRole` scoped to `elasticloadbalancing.amazonaws.com` service condition
- ExternalDNS: Route53 scoped to specific zone IDs (not `hostedzone/*`)
- Karpenter: EC2 describe scoped to account

## After Modules — Account Config Refactor

Once modules are built, each account's config becomes thin orchestration:

```hcl
# accounts/dev/global/iam/main.tf (~15 lines)
module "account_base" {
  source           = "git::...//modules/conservice-account-base?ref=v1.0.0"
  env              = var.env
  aws_account_id   = var.aws_account_id
  tools_account_id = var.tools_account_id
}

# accounts/dev/us-east-1/vpc/main.tf (~15 lines)
module "network" {
  source             = "git::...//modules/conservice-vpc-network?ref=v1.0.0"
  env                = var.env
  vpc_cidr           = var.vpc_cidr
  azs                = var.azs
  transit_gateway_id = var.transit_gateway_id
}

# accounts/dev/us-east-1/services/eks-workload/main.tf (~25 lines)
module "eks" {
  source       = "git::...//modules/conservice-eks-cluster?ref=v1.0.0"
  cluster_name = "conservice-dev-workload"
  env          = var.env
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_app_subnet_ids
  cluster_role_arn = local.eks_cluster_role_arn
  node_role_arn    = local.eks_node_role_arn
}

module "eks_addons" {
  source       = "git::...//modules/conservice-eks-addons?ref=v1.0.0"
  cluster_name = module.eks.cluster_name
  cluster_arn  = module.eks.cluster_arn
  env          = var.env
  aws_account_id = var.aws_account_id
  node_role_arn  = local.eks_node_role_arn
  route53_zone_ids = [local.platform_zone_id, local.public_zone_id]
}
```

## Tools Account — Special Cases

The tools account has configs that don't repeat in workload accounts:
- **TGW hub creation** (tools/us-east-1/vpc/ creates the TGW, others attach to it)
- **ECR repos** (tools/global/ecr/)
- **Route53 zones** (tools/global/route53/)
- **KMS shared keys** (tools/global/kms/)
- **ACM certs** (tools/us-east-1/acm/)
- **Prefix lists** (tools/us-east-1/prefix-lists/)
- **us-west-2 VPC** (tools/us-west-2/vpc/ with TGW peering)

These stay as custom configs — they're genuinely unique to the tools account.
