##############################################################################
# variables.tf – shared variable declarations for the dev environment
# (identical structure is reused in prod/variables.tf with different defaults)
##############################################################################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short identifier used in all resource names"
  type        = string
  default     = "hotel-app"
}

variable "environment" {
  description = "Deployment environment label"
  type        = string
  default     = "dev"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_ecs_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_rds_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

# ── Application ───────────────────────────────────────────────────────────────

variable "container_image" {
  type    = string
  default = "nginx:alpine"
}

variable "container_port" {
  type    = number
  default = 80
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 2
}

variable "log_retention_days" {
  type    = number
  default = 7
}

# ── RDS ───────────────────────────────────────────────────────────────────────

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "dbadmin"
}

variable "db_password" {
  description = "SENSITIVE: provide via TF_VAR_db_password env var or -var flag"
  type        = string
  sensitive   = true
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "rds_allocated_storage" {
  type    = number
  default = 20
}

variable "backup_retention_period" {
  type    = number
  default = 3
}

# ── Prod-only (unused in dev, present for variable parity) ───────────────────

variable "https_certificate_arn" {
  type    = string
  default = ""
}
