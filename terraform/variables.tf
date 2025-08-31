variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "11.0.0.0/16"
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["11.0.1.0/24", "11.0.2.0/24"]
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["11.0.3.0/24", "11.0.4.0/24"]
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "database_name" {
  description = "Name of the database"
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

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "wordpress"
}

variable "domain_name" {
  description = "Domain name for the WordPress site"
  type        = string
}

variable "task_cpu" {
  description = "CPU units for the ECS task"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory for the ECS task"
  type        = number
  default     = 512
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "nginx_image" {
  description = "Nginx container image"
  type        = string
  default     = "nginx:1.21-alpine"
}

variable "wordpress_image" {
  description = "WordPress container image"
  type        = string
  default     = "wordpress:5.9-fpm-alpine"
}

variable "container_port" {
  description = "Container port for Nginx"
  type        = number
  default     = 80
}

variable "wordpress_memory" {
  description = "Memory for WordPress container"
  type        = number
  default     = 256
}

variable "nginx_memory" {
  description = "Memory for Nginx container"
  type        = number
  default     = 256
}
