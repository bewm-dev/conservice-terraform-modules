# -----------------------------------------------------------------------------
# Kinesis Data Firehose — native resources
#
# Delivers app events to S3 via buffered Firehose streams. Each firehose
# targets one of the app's declared S3 buckets (must exist in `buckets`).
#
# Pod gets firehose:PutRecord + firehose:PutRecordBatch on all streams.
# Firehose itself gets its own IAM role scoped to write to the target bucket.
#
# Naming: csvc-{env}-{region_code}-{app_name}-{key}
# -----------------------------------------------------------------------------

locals {
  firehoses = local.use_yaml ? lookup(local.env_override, "firehoses", lookup(local.config, "firehoses", {})) : var.firehoses

  firehose_names = {
    for k, _ in local.firehoses : k => "${local.name_prefix}-${k}"
  }

  firehose_role_names = {
    for k, _ in local.firehoses : k => length(local.firehoses) == 1 ? "${local.app_role_prefix}-firehose-role" : "${local.app_role_prefix}-firehose-${k}-role"
  }
}

resource "aws_iam_role" "firehose" {
  for_each = local.firehoses

  name = local.firehose_role_names[each.key]
  path = "/apps/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = local.firehose_role_names[each.key]
  })
}

resource "aws_iam_role_policy" "firehose_s3" {
  for_each = local.firehoses

  name = "s3-delivery"
  role = aws_iam_role.firehose[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject",
      ]
      Resource = [
        module.s3_buckets[each.value.bucket].s3_bucket_arn,
        "${module.s3_buckets[each.value.bucket].s3_bucket_arn}/*",
      ]
    }]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "app" {
  for_each = local.firehoses

  name        = local.firehose_names[each.key]
  destination = "extended_s3"

  extended_s3_configuration {
    bucket_arn         = module.s3_buckets[each.value.bucket].s3_bucket_arn
    role_arn           = aws_iam_role.firehose[each.key].arn
    prefix             = lookup(each.value, "prefix", "")
    buffering_size     = lookup(each.value, "buffer_size_mb", 5)
    buffering_interval = lookup(each.value, "buffer_interval_seconds", 300)
    compression_format = lookup(each.value, "compression", "GZIP")
  }

  lifecycle {
    precondition {
      condition     = contains(keys(local.buckets), each.value.bucket)
      error_message = "firehose '${each.key}' references bucket '${each.value.bucket}' which is not declared in resources.buckets."
    }
  }

  tags = merge(local.common_tags, {
    Name = local.firehose_names[each.key]
  })
}
