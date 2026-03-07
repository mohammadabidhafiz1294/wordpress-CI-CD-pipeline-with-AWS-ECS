output "alb_public_security_group_id" {
  description = "Security group ID for Public ALB"
  value       = aws_security_group.alb_public.id
}

output "alb_internal_security_group_id" {
  description = "Security group ID for Internal ALB (Admin)"
  value       = aws_security_group.alb_internal.id
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs.id
}

output "ec2_admin_security_group_id" {
  description = "Security group ID for EC2 Admin"
  value       = aws_security_group.ec2_admin.id
}

output "database_security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.database.id
}
