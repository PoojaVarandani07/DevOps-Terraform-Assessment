##############################################################################
# Environment: dev
# Wires the three modules together with dev-appropriate sizing.
##############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state – use an S3 backend per environment so state files never mix.
  # Fill in the bucket/key/region before running `terraform init`.
  backend "s3" {
    bucket         = "my-terraform-state-dev"
    key            = "devops-assessment/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "devops-team"
  }
}

# ── Network ───────────────────────────────────────────────────────────────────

module "network" {
  source = "../../modules/network"

  project_name             = var.project_name
  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_ecs_subnet_cidrs = var.private_ecs_subnet_cidrs
  private_rds_subnet_cidrs = var.private_rds_subnet_cidrs
  enable_nat_gateway       = var.enable_nat_gateway
  container_port           = var.container_port
  tags                     = local.common_tags
}

# ── ALB ───────────────────────────────────────────────────────────────────────

module "alb" {
  source = "../../modules/alb"

  project_name               = var.project_name
  environment                = var.environment
  vpc_id                     = module.network.vpc_id
  public_subnet_ids          = module.network.public_subnet_ids
  alb_security_group_id      = module.network.alb_security_group_id
  container_port             = var.container_port
  health_check_path          = var.health_check_path
  enable_deletion_protection = false  # dev: allow destroy
  tags                       = local.common_tags
}

# ── ECS / Fargate ─────────────────────────────────────────────────────────────

module "ecs" {
  source = "../../modules/ecs"

  project_name          = var.project_name
  environment           = var.environment
  private_subnet_ids    = module.network.private_ecs_subnet_ids
  ecs_security_group_id = module.network.ecs_security_group_id
  target_group_arn      = module.alb.target_group_arn

  container_image  = var.container_image
  container_port   = var.container_port
  task_cpu         = var.task_cpu
  task_memory      = var.task_memory
  desired_count    = var.desired_count
  min_capacity     = var.min_capacity
  max_capacity     = var.max_capacity
  log_retention_days = var.log_retention_days

  # Pass the DB connection string from Secrets Manager
  container_secrets = {
    DB_SECRET_ARN = module.rds.db_secret_arn
  }

  container_env = {
    APP_ENV = var.environment
    DB_HOST = module.rds.db_instance_address
    DB_NAME = var.db_name
    DB_PORT = "5432"
  }

  enable_container_insights = false  # save cost in dev
  enable_execute_command    = true   # useful for debugging in dev
  use_fargate_spot          = true   # cheaper in dev
  tags                      = local.common_tags
}

# ── RDS PostgreSQL ────────────────────────────────────────────────────────────

module "rds" {
  source = "../../modules/rds"

  project_name           = var.project_name
  environment            = var.environment
  private_rds_subnet_ids = module.network.private_rds_subnet_ids
  rds_security_group_id  = module.network.rds_security_group_id

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  instance_class          = var.rds_instance_class
  allocated_storage       = var.rds_allocated_storage
  multi_az                = false  # single-AZ is fine for dev
  backup_retention_period = var.backup_retention_period
  deletion_protection     = false  # dev: allow destroy
  skip_final_snapshot     = true   # dev: no final snapshot needed

  enable_enhanced_monitoring  = false
  enable_performance_insights = false

  tags = local.common_tags
}
