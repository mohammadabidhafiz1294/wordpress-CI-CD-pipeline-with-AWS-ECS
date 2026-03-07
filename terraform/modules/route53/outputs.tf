output "zone_id" {
  description = "Zone ID of the Route53 hosted zone"
  value       = aws_route53_zone.wordpress.zone_id
}
