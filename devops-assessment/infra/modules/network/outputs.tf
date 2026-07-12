output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (ALB)"
  value       = aws_subnet.public[*].id
}

output "private_ecs_subnet_ids" {
  description = "List of private ECS subnet IDs"
  value       = aws_subnet.private_ecs[*].id
}

output "private_rds_subnet_ids" {
  description = "List of private RDS subnet IDs"
  value       = aws_subnet.private_rds[*].id
}

output "alb_security_group_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}
