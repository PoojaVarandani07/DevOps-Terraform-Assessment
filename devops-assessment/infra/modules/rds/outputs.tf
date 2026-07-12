output "db_instance_id"       { value = aws_db_instance.this.id }
output "db_instance_address"  { value = aws_db_instance.this.address }
output "db_instance_endpoint" { value = aws_db_instance.this.endpoint }
output "db_name"              { value = aws_db_instance.this.db_name }
output "db_secret_arn"        { value = aws_secretsmanager_secret.db_password.arn }
output "kms_key_arn"          { value = aws_kms_key.rds.arn }
