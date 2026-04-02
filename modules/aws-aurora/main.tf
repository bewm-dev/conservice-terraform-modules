# -----------------------------------------------------------------------------
# Preset Defaults
# -----------------------------------------------------------------------------

locals {
  presets = {
    lean = {
      min_capacity            = 0.5
      max_capacity            = 4
      backup_retention_period = 7
      deletion_protection     = false
      skip_final_snapshot     = true
      instance_count          = 1
      instance_class          = "db.serverless"
    }
    single = {
      min_capacity            = 1
      max_capacity            = 8
      backup_retention_period = 14
      deletion_protection     = true
      skip_final_snapshot     = false
      instance_count          = 1
      instance_class          = "db.serverless"
    }
    high-availability = {
      min_capacity            = 2
      max_capacity            = 32
      backup_retention_period = 35
      deletion_protection     = true
      skip_final_snapshot     = false
      instance_count          = 2
      instance_class          = "db.serverless"
    }
  }

  preset = local.presets[var.preset]

  # Variable overrides take precedence over preset defaults
  min_capacity            = coalesce(var.min_capacity, local.preset.min_capacity)
  max_capacity            = coalesce(var.max_capacity, local.preset.max_capacity)
  backup_retention_period = coalesce(var.backup_retention_period, local.preset.backup_retention_period)
  deletion_protection     = coalesce(var.deletion_protection, local.preset.deletion_protection)
  skip_final_snapshot     = coalesce(var.skip_final_snapshot, local.preset.skip_final_snapshot)
  instance_count          = coalesce(var.instance_count, local.preset.instance_count)
  instance_class          = coalesce(var.instance_class, local.preset.instance_class)

  # Derive parameter group family from engine version (e.g. "16.4" -> "aurora-postgresql16")
  pg_major_version     = split(".", var.engine_version)[0]
  parameter_group_family = "aurora-postgresql${local.pg_major_version}"
}

# -----------------------------------------------------------------------------
# KMS Key
# -----------------------------------------------------------------------------

resource "aws_kms_key" "aurora" {
  description             = "KMS key for Aurora encryption - ${var.cluster_name}"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-kms"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${var.cluster_name}"
  target_key_id = aws_kms_key.aurora.key_id
}

# -----------------------------------------------------------------------------
# DB Subnet Group
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.cluster_name}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-subnet-group"
  })
}

# -----------------------------------------------------------------------------
# Parameter Groups
# -----------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.cluster_name}-cluster-params"
  family      = local.parameter_group_family
  description = "Cluster parameter group for ${var.cluster_name}"

  # Standard parameters — log DDL and slow queries, enable pg_stat_statements
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  # Additional parameters from variable
  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-params"
  })
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.cluster_name}-instance-params"
  family      = local.parameter_group_family
  description = "Instance parameter group for ${var.cluster_name}"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  dynamic "parameter" {
    for_each = var.instance_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-instance-params"
  })
}

# -----------------------------------------------------------------------------
# Enhanced Monitoring IAM Role (conditional)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "enhanced_monitoring" {
  count = var.enhanced_monitoring_interval > 0 ? 1 : 0

  name = "${var.cluster_name}-rds-monitoring"
  path = "/rds/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-rds-monitoring"
  })
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.enhanced_monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# Aurora Serverless v2 Cluster
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.cluster_name
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = var.engine_version
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password

  db_subnet_group_name            = aws_db_subnet_group.this.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  vpc_security_group_ids          = var.vpc_security_group_ids

  storage_encrypted = true
  kms_key_id        = aws_kms_key.aurora.arn

  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  backup_retention_period   = local.backup_retention_period
  preferred_backup_window   = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  deletion_protection       = local.deletion_protection
  skip_final_snapshot       = local.skip_final_snapshot
  final_snapshot_identifier = local.skip_final_snapshot ? null : "${var.cluster_name}-final-snapshot"

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  serverlessv2_scaling_configuration {
    min_capacity = local.min_capacity
    max_capacity = local.max_capacity
  }

  tags = merge(var.tags, {
    Name = var.cluster_name
  })

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Cluster Instances
# -----------------------------------------------------------------------------

resource "aws_rds_cluster_instance" "this" {
  count = local.instance_count

  identifier         = "${var.cluster_name}-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = local.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_parameter_group_name = aws_db_parameter_group.this.name

  performance_insights_enabled = var.performance_insights_enabled

  monitoring_interval = var.enhanced_monitoring_interval
  monitoring_role_arn = var.enhanced_monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-instance-${count.index + 1}"
  })
}
