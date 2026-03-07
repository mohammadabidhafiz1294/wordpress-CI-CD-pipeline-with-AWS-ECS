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

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.wordpress.arn
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.wordpress.arn
}
