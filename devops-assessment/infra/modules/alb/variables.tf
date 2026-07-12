variable "project_name"          { type = string }
variable "environment"           { type = string }
variable "vpc_id"                { type = string }
variable "public_subnet_ids"     { type = list(string) }
variable "alb_security_group_id" { type = string }
variable "container_port"        { type = number; default = 80 }
variable "health_check_path"     { type = string; default = "/" }
variable "https_certificate_arn" { type = string; default = "" }
variable "enable_deletion_protection" { type = bool; default = false }
variable "access_log_bucket"     { type = string; default = "" }
variable "tags"                  { type = map(string); default = {} }
