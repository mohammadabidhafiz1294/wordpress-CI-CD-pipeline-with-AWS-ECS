output "application_name" {
  description = "CodeDeploy application name"
  value       = aws_codedeploy_app.wordpress.name
}

output "application_id" {
  description = "CodeDeploy application ID"
  value       = aws_codedeploy_app.wordpress.arn
}

output "deployment_group_name" {
  description = "CodeDeploy deployment group name"
  value       = aws_codedeploy_deployment_group.wordpress.deployment_group_name
}

output "deployment_group_id" {
  description = "CodeDeploy deployment group ID"
  value       = aws_codedeploy_deployment_group.wordpress.id
}

output "service_role_arn" {
  description = "IAM role ARN for CodeDeploy"
  value       = aws_iam_role.codedeploy.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN for notifications"
  value       = aws_sns_topic.codedeploy.arn
}
