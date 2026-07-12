##############################################################################
# dev.tfvars – developer-facing values (safe to commit; no secrets)
##############################################################################

aws_region   = "us-east-1"
project_name = "hotel-app"
environment  = "dev"

# Networking
vpc_cidr                 = "10.0.0.0/16"
availability_zones       = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
private_ecs_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
private_rds_subnet_cidrs = ["10.0.20.0/24", "10.0.21.0/24"]
enable_nat_gateway       = true

# Application (using nginx as a placeholder)
container_image    = "nginx:alpine"
container_port     = 80
health_check_path  = "/"
task_cpu           = 256
task_memory        = 512
desired_count      = 1
min_capacity       = 1
max_capacity       = 2
log_retention_days = 7

# RDS – small instance, short backup window, no deletion protection
db_name               = "appdb"
db_username           = "dbadmin"
# db_password         → set via: export TF_VAR_db_password="..."
rds_instance_class      = "db.t3.micro"
rds_allocated_storage   = 20
backup_retention_period = 3
