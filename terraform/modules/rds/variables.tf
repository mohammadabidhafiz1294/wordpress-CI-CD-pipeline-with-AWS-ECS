variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "database_security_group_id" {
  description = "Security group ID for RDS"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
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
