variable "aws_region"   { type = string; default = "us-east-1" }
variable "project_name" { type = string; default = "hotel-app" }
variable "environment"  { type = string; default = "prod" }

variable "vpc_cidr"                 { type = string }
variable "availability_zones"       { type = list(string) }
variable "public_subnet_cidrs"      { type = list(string) }
variable "private_ecs_subnet_cidrs" { type = list(string) }
variable "private_rds_subnet_cidrs" { type = list(string) }
variable "enable_nat_gateway"       { type = bool; default = true }

variable "container_image"    { type = string }
variable "container_port"     { type = number; default = 80 }
variable "health_check_path"  { type = string; default = "/" }
variable "https_certificate_arn" { type = string; default = "" }

variable "task_cpu"           { type = number }
variable "task_memory"        { type = number }
variable "desired_count"      { type = number }
variable "min_capacity"       { type = number }
variable "max_capacity"       { type = number }
variable "log_retention_days" { type = number; default = 90 }

variable "db_name"                  { type = string; default = "appdb" }
variable "db_username"              { type = string; default = "dbadmin" }
variable "db_password"              { type = string; sensitive = true }
variable "rds_instance_class"       { type = string }
variable "rds_allocated_storage"    { type = number }
variable "backup_retention_period"  { type = number }
