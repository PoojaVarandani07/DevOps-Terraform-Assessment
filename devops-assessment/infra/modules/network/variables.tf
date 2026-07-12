variable "project_name" {
  description = "Short project identifier used in resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to spread subnets across (minimum 2 for RDS)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "One CIDR per AZ for public subnets (ALB)"
  type        = list(string)
}

variable "private_ecs_subnet_cidrs" {
  description = "One CIDR per AZ for private ECS subnets"
  type        = list(string)
}

variable "private_rds_subnet_cidrs" {
  description = "One CIDR per AZ for private RDS subnets"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway so private subnets have outbound internet access"
  type        = bool
  default     = true
}

variable "container_port" {
  description = "Port the application container listens on"
  type        = number
  default     = 80
}

variable "tags" {
  description = "Common tags applied to every resource"
  type        = map(string)
  default     = {}
}
