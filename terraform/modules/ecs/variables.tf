variable "service_name" {
  description = "Name of the ECS service"
  type        = string
  default     = "wordpress"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "capacity_provider" {
  description = "Capacity provider (FARGATE or FARGATE_SPOT)"
  type        = string
  default     = "FARGATE"
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "wordpress-cluster"
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for ECS tasks"
  type        = list(string)
}

variable "task_cpu" {
  description = "CPU units for the task"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory for the task"
  type        = number
  default     = 512
}

variable "nginx_image" {
  description = "Nginx container image"
  type        = string
  default     = "nginx:1.25-alpine"
}

variable "wordpress_image" {
  description = "WordPress container image"
  type        = string
  default     = "wordpress:6.4.3-php8.2-fpm-alpine"
}

variable "wordpress_memory" {
  description = "Memory for WordPress container"
  type        = number
  default     = 256
}

variable "efs_filesystem_id" {
  description = "ID of the EFS filesystem"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

variable "target_group_arn" {
  description = "ARN of ALB target group"
  type        = string
  default     = ""
}

variable "service_desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

variable "database_endpoint" {
  description = "RDS endpoint"
  type        = string
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "wordpress"
}

variable "database_user" {
  description = "Database username"
  type        = string
  default     = "wordpress"
}

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

# =============================================================================
# AUTO-SCALING VARIABLES - COMMENTED OUT
# Uncomment if you need auto-scaling functionality
# =============================================================================
# variable "autoscaling_enabled" {
#   description = "Enable auto-scaling for ECS service"
#   type        = bool
#   default     = false
# }
# 
# variable "autoscaling_min_capacity" {
#   description = "Minimum number of tasks for auto-scaling"
#   type        = number
#   default     = 1
# }
# 
# variable "autoscaling_max_capacity" {
#   description = "Maximum number of tasks for auto-scaling"
#   type        = number
#   default     = 4
# }
# 
# variable "autoscaling_target_cpu_utilization" {
#   description = "Target CPU utilization percentage for auto-scaling"
#   type        = number
#   default     = 70
# }
# 
# variable "autoscaling_target_memory_utilization" {
#   description = "Target memory utilization percentage for auto-scaling"
#   type        = number
#   default     = 70
# }
# =============================================================================
