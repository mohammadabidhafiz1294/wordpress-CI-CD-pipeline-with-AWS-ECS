output "efs_id" {
  description = "ID of the EFS filesystem"
  value       = aws_efs_file_system.wordpress.id
}

output "efs_dns_name" {
  description = "DNS name of the EFS filesystem"
  value       = aws_efs_file_system.wordpress.dns_name
}

output "efs_security_group_id" {
  description = "Security group ID for EFS"
  value       = aws_security_group.efs.id
}

output "access_point_id" {
  description = "ID of the EFS access point"
  value       = aws_efs_access_point.wp_content.id
}
