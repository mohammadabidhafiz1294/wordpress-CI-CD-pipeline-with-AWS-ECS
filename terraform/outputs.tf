// Output values for the WordPress ECS project

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = module.alb.alb_dns_name
}

output "public_url" {
  description = "Public URL of the WordPress site"
  value       = "http://${var.domain_name}"
}

output "admin_url" {
  description = "Admin URL of the WordPress site"
  value       = "http://admin.${var.domain_name}"
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.ecr.repository_url
}

output "rds_endpoint" {
  description = "Endpoint of the RDS instance"
  value       = module.rds.endpoint
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_primary.cluster_name
}

output "ecs_primary_service_name" {
  description = "Name of the primary ECS service"
  value       = module.ecs_primary.service_name
}

output "ecs_backup_service_name" {
  description = "Name of the backup ECS service"
  value       = module.ecs_backup.service_name
}

output "efs_dns_name" {
  description = "DNS name of the EFS filesystem"
  value       = module.efs.efs_dns_name
}

output "ec2_admin_instance_id" {
  description = "ID of the EC2 admin instance"
  value       = module.ec2_admin.instance_id
}
