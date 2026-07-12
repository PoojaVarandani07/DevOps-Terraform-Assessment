variable "project_name"  { type = string }
variable "environment"   { type = string }

variable "private_rds_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the RDS subnet group (must span ≥2 AZs)"
}

variable "rds_security_group_id" {
  type        = string
  description = "Security group that allows ECS → RDS on 5432"
}

variable "db_name" {
  type        = string
  description = "Name of the initial database"
  default     = "appdb"
}

variable "db_username" {
  type        = string
  description = "Master username for RDS"
  default     = "dbadmin"
}

variable "db_password" {
  type        = string
  description = "Master password (use Secrets Manager in real environments)"
  sensitive   = true
}

variable "engine_version" {
  type    = string
  default = "16.2"
}

variable "instance_class" {
  type        = string
  description = "RDS instance type (e.g. db.t3.micro, db.r6g.large)"
}

variable "allocated_storage" {
  type        = number
  description = "Storage in GB"
  default     = 20
}

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ for high availability"
  default     = false
}

variable "backup_retention_period" {
  type        = number
  description = "Days to keep automated backups (0 disables backups)"
}

variable "deletion_protection" {
  type        = bool
  description = "Prevent accidental deletion of the DB instance"
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Skip the final snapshot when destroying (set true only in dev)"
  default     = false
}

variable "enable_enhanced_monitoring" {
  type    = bool
  default = false
}

variable "enable_performance_insights" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
