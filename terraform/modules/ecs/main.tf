resource "aws_ecs_cluster" "wordpress" {
  name = "wordpress-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "wordpress" {
  cluster_name = aws_ecs_cluster.wordpress.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 1
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "wordpress" {
  family                   = "wordpress"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = var.nginx_image
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/wordpress"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "nginx"
        }
      }
    },
    {
      name      = "wordpress"
      image     = var.wordpress_image
      essential = true
      memory    = var.wordpress_memory
      environment = [
        {
          name  = "WORDPRESS_DB_HOST"
          value = var.database_endpoint
        },
        {
          name  = "WORDPRESS_DB_USER"
          value = var.database_user
        },
        {
          name  = "WORDPRESS_DB_PASSWORD"
          value = var.database_password
        },
        {
          name  = "WORDPRESS_DB_NAME"
          value = var.database_name
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "wp-content"
          containerPath = "/var/www/html/wp-content"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/wordpress"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "wordpress"
        }
      }
    }
  ])

  volume {
    name = "wp-content"
    efs_volume_configuration {
      file_system_id     = var.efs_filesystem_id
      root_directory     = "/wp-content"
      transit_encryption = "ENABLED"
    }
  }

  tags = {
    Name        = "wordpress-task"
    Environment = var.environment
  }
}

resource "aws_ecs_service" "wordpress" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.wordpress.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = var.service_desired_count

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    base              = var.capacity_provider == "FARGATE" ? 1 : 0
    weight            = var.capacity_provider == "FARGATE" ? 1 : 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [aws_lb_target_group.wordpress]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = replace("${var.service_name}-tg", "/", "-")
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/wp-content/plugins/"
    matcher             = "200"
  }

  tags = {
    Name = "${var.service_name}-target-group"
  }
}

# =============================================================================
# AUTO-SCALING - COMMENTED OUT
# Uncomment these resources if you need auto-scaling functionality
# =============================================================================

# =============================================================================
# # ECS Service Auto-Scaling Target
# resource "aws_appautoscaling_target" "ecs_target" {
#   max_capacity       = var.autoscaling_max_capacity
#   min_capacity       = var.autoscaling_min_capacity
#   resource_id        = "service/${aws_ecs_cluster.wordpress.name}/${aws_ecs_service.wordpress.name}"
#   scalable_dimension = "ecs:service:DesiredCount"
#   service_namespace  = "ecs"
# }
# 
# # CPU-based Scaling Policy
# resource "aws_appautoscaling_policy" "ecs_scale_up" {
#   name               = "wordpress-cpu-scale-up"
#   policy_type        = "TargetTrackingScaling"
#   resource_id        = aws_appautoscaling_target.ecs_target.resource_id
#   scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
#   service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
# 
#   target_tracking_scaling_policy_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ECSServiceAverageCPUUtilization"
#     }
#     target_value       = 70
#     scale_in_cooldown = 60
#     scale_out_cooldown = 60
#   }
# }
# 
# # Memory-based Scaling Policy
# resource "aws_appautoscaling_policy" "ecs_scale_up_memory" {
#   name               = "wordpress-memory-scale-up"
#   policy_type        = "TargetTrackingScaling"
#   resource_id        = aws_appautoscaling_target.ecs_target.resource_id
#   scalable_dimension =caling_target.ecs aws_appautos_target.scalable_dimension
#   service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
# 
#   target_tracking_scaling_policy_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ECSServiceAverageMemoryUtilization"
#     }
#     target_value       = 70
#     scale_in_cooldown = 60
#     scale_out_cooldown = 60
#   }
# }
# =============================================================================
