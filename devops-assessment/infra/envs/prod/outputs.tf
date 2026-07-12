output "vpc_id"          { value = module.network.vpc_id }
output "alb_dns_name"    { value = module.alb.alb_dns_name }
output "ecs_cluster"     { value = module.ecs.cluster_name }
output "rds_endpoint"    { value = module.rds.db_instance_endpoint }
output "db_secret_arn"   { value = module.rds.db_secret_arn }
