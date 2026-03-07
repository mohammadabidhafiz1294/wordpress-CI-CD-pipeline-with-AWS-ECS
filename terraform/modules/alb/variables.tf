variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "public_domain_name" {
  description = "Public domain name (e.g., yourdomain.com)"
  type        = string
}

variable "admin_domain_name" {
  description = "Admin domain name (e.g., admin.yourdomain.com)"
  type        = string
}

variable "health_check_path" {
  description = "Health check path for target group"
  type        = string
  default     = "/"
}
