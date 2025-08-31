output "alb_dns_name" {
  description = "DNS name of ALB"
  value       = aws_lb.wordpress.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of ALB"
  value       = aws_lb.wordpress.zone_id
}

output "target_group_arn" {
  description = "ARN of target group"
  value       = aws_lb_target_group.wordpress.arn
}

output "alb_arn" {
  description = "ARN of ALB"
  value       = aws_lb.wordpress.arn
}
