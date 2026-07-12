variable "project_name"    { type = string }
variable "environment"     { type = string }

variable "private_subnet_ids" {
  description = "Subnets where Fargate tasks are placed (private-ecs)"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group attached to Fargate tasks"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group ARN the service registers into"
  type        = string
}

variable "container_name" {
  description = "Name used inside the task definition"
  type        = string
  default     = "app"
}

variable "container_image" {
  description = "Docker image URI (e.g. nginx:alpine or 123456.dkr.ecr.us-east-1.amazonaws.com/app:latest)"
  type        = string
  default     = "nginx:alpine"
}

variable "container_port" {
  description = "Port the container exposes"
  type        = number
  default     = 80
}

variable "container_env" {
  description = "Plain-text environment variables injected into the container"
  type        = map(string)
  default     = {}
}

variable "container_secrets" {
  description = "Secrets Manager / SSM ARNs exposed as env vars (name → ARN)"
  type        = map(string)
  default     = {}
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 | 512 | 1024 | 2048 | 4096)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Initial number of running tasks"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum tasks for auto-scaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum tasks for auto-scaling"
  type        = number
  default     = 4
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "enable_container_insights" {
  description = "Enable ECS Container Insights metrics"
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Allow `aws ecs execute-command` into running tasks (debugging)"
  type        = bool
  default     = false
}

variable "use_fargate_spot" {
  description = "Use FARGATE_SPOT capacity provider (cheaper, interruptible)"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
