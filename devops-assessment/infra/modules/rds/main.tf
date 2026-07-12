##############################################################################
# Module: rds
# Creates a PostgreSQL RDS instance in private subnets.
# The instance is NOT publicly accessible; only the ECS security group
# is allowed to reach port 5432 (enforced at the network layer).
##############################################################################

locals {
  name_pfx = "${var.project_name}-${var.environment}"
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "this" {
  name        = "${local.name_pfx}-db-subnet-group"
  description = "RDS subnet group for ${local.name_pfx}"
  subnet_ids  = var.private_rds_subnet_ids

  tags = merge(var.tags, { Name = "${local.name_pfx}-db-subnet-group" })
}

# ── DB Parameter Group ────────────────────────────────────────────────────────

resource "aws_db_parameter_group" "this" {
  name        = "${local.name_pfx}-pg-params"
  family      = "postgres16"
  description = "Custom parameters for ${local.name_pfx}"

  # Enable query logging for slow queries (≥ 1 second)
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, { Name = "${local.name_pfx}-pg-params" })
}

# ── KMS Key for encryption at rest ────────────────────────────────────────────

resource "aws_kms_key" "rds" {
  description             = "KMS key for ${local.name_pfx} RDS encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${local.name_pfx}-rds-kms" })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${local.name_pfx}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# ── Secrets Manager – DB credentials ─────────────────────────────────────────

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${local.name_pfx}/rds/master-password"
  description             = "RDS master password for ${local.name_pfx}"
  recovery_window_in_days = var.deletion_protection ? 30 : 0
  kms_key_id              = aws_kms_key.rds.arn
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    engine   = "postgres"
    host     = aws_db_instance.this.address
    port     = 5432
    dbname   = var.db_name
  })
}

# ── RDS PostgreSQL Instance ───────────────────────────────────────────────────

resource "aws_db_instance" "this" {
  identifier = "${local.name_pfx}-postgres"

  # Engine
  engine               = "postgres"
  engine_version       = var.engine_version
  parameter_group_name = aws_db_parameter_group.this.name

  # Sizing
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  # Credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Networking – PRIVATE, not accessible from the internet
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  # Backup & Maintenance
  backup_retention_period   = var.backup_retention_period
  backup_window             = "02:00-03:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_pfx}-final-snapshot"
  deletion_protection       = var.deletion_protection

  # Monitoring
  monitoring_interval             = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn             = var.enable_enhanced_monitoring ? aws_iam_role.rds_monitoring[0].arn : null
  performance_insights_enabled    = var.enable_performance_insights
  performance_insights_kms_key_id = var.enable_performance_insights ? aws_kms_key.rds.arn : null
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Auto minor version upgrades (safe in prod)
  auto_minor_version_upgrade = true

  tags = merge(var.tags, { Name = "${local.name_pfx}-postgres" })
}

# ── Enhanced Monitoring IAM Role (optional) ───────────────────────────────────

resource "aws_iam_role" "rds_monitoring" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  name  = "${local.name_pfx}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count      = var.enable_enhanced_monitoring ? 1 : 0
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
