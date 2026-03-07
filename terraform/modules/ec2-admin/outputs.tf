output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.wordpress_admin.id
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance"
  value       = aws_instance.wordpress_admin.private_ip
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.ec2_admin.arn
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_admin.name
}
