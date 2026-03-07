variable "application_name" {
  description = "Name of the CodeDeploy application"
  type        = string
  default     = "wordpress-ecs"
}

variable "deployment_group_name" {
  description = "Name of the deployment group"
  type        = string
  default     = "wordpress-production"
}

variable "deployment_config_name" {
  description = "Deployment configuration name"
  type        = string
  default     = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
}

variable "alb_listener_arn" {
  description = "ALB listener ARN for production traffic"
  type        = string
}

variable "blue_target_group_name" {
  description = "Blue target group name (current production)"
  type        = string
  default     = "wordpress-blue-tg"
}

variable "green_target_group_name" {
  description = "Green target group name (new deployment)"
  type        = string
  default     = "wordpress-green-tg"
}

variable "canary_percentage" {
  description = "Percentage of traffic for canary deployment"
  type        = number
  default     = 10
}

variable "step_interval_in_minutes" {
  description = "Interval between traffic shifts in minutes"
  type        = number
  default     = 1
}

variable "wait_time_in_minutes" {
  description = "Wait time before traffic routing completes"
  type        = number
  default     = 5
}

variable "termination_wait_time_in_minutes" {
  description = "Wait time before terminating blue instances after successful deployment"
  type        = number
  default     = 60
}

variable "action_on_timeout" {
  description = "Action to take when deployment ready timeout occurs"
  type        = string
  default     = "CONTINUE_DEPLOYMENT"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "enable_rollback_on_alarms" {
  description = "Enable rollback on CloudWatch alarms"
  type        = bool
  default     = false
}

variable "alarm_arns" {
  description = "List of CloudWatch alarm ARNs for rollback"
  type        = list(string)
  default     = []
}
