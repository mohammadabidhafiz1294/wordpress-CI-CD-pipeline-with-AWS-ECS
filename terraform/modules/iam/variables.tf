variable "execution_role_name" {
  description = "Name of the ECS execution role"
  type        = string
  default     = "wordpress-ecs-execution-role"
}

variable "task_role_name" {
  description = "Name of the ECS task role"
  type        = string
  default     = "wordpress-ecs-task-role"
}
