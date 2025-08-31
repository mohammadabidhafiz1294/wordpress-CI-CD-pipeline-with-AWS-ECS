output "cluster_id" {
  description = "ID of ECS cluster"
  value       = aws_ecs_cluster.wordpress.id
}

output "cluster_name" {
  description = "Name of ECS cluster"
  value       = aws_ecs_cluster.wordpress.name
}

output "service_name" {
  description = "Name of ECS service"
  value       = aws_ecs_service.wordpress.name
}
