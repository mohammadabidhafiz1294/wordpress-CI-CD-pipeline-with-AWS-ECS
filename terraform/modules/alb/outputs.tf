output "alb_dns_name" {
  description = "DNS name of ALB"
  value       = aws_lb.wordpress.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of ALB"
  value       = aws_lb.wordpress.zone_id
}

output "alb_arn" {
  description = "ARN of ALB"
  value       = aws_lb.wordpress.arn
}

output "listener_arn" {
  description = "ARN of the ALB listener"
  value       = aws_lb_listener.wordpress.arn
}

output "blue_target_group_arn" {
  description = "ARN of blue target group (current production)"
  value       = aws_lb_target_group.blue.arn
}

output "green_target_group_arn" {
  description = "ARN of green target group (new deployment)"
  value       = aws_lb_target_group.green.arn
}

output "blue_target_group_name" {
  description = "Name of blue target group"
  value       = aws_lb_target_group.blue.name
}

output "green_target_group_name" {
  description = "Name of green target group"
  value       = aws_lb_target_group.green.name
}

output "ec2_admin_target_group_arn" {
  description = "ARN of EC2 Admin target group"
  value       = aws_lb_target_group.ec2_admin.arn
}
