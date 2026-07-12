##############################################################################
# prod.tfvars – production values (safe to commit; no secrets)
##############################################################################

aws_region   = "us-east-1"
project_name = "hotel-app"
environment  = "prod"

# Networking (non-overlapping with dev)
vpc_cidr                 = "10.1.0.0/16"
availability_zones       = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs      = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
private_ecs_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
private_rds_subnet_cidrs = ["10.1.20.0/24", "10.1.21.0/24", "10.1.22.0/24"]
enable_nat_gateway       = true

# Application
container_image       = "nginx:alpine"   # replace with ECR image in real prod
container_port        = 80
health_check_path     = "/"
https_certificate_arn = ""               # add ACM ARN to enable HTTPS redirect
task_cpu              = 1024
task_memory           = 2048
desired_count         = 2
min_capacity          = 2
max_capacity          = 10
log_retention_days    = 90

# RDS – larger instance, Multi-AZ, long backup, deletion protection
db_name               = "appdb"
db_username           = "dbadmin"
# db_password         → set via: export TF_VAR_db_password="..."
rds_instance_class      = "db.r6g.large"
rds_allocated_storage   = 100
backup_retention_period = 30
