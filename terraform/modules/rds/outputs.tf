output "endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.wordpress.endpoint
}

output "database_name" {
  description = "Database name"
  value       = aws_db_instance.wordpress.db_name
}

output "database_user" {
  description = "Database username"
  value       = aws_db_instance.wordpress.username
}
