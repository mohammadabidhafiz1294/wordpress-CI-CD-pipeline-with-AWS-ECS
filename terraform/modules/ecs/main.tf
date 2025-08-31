resource "aws_ecs_cluster" "wordpress" {
  name = "wordpress-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "wordpress" {
  family                   = "wordpress"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = var.task_cpu
  memory                  = var.task_memory
  execution_role_arn      = var.execution_role_arn
  task_role_arn           = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = "nginx:alpine"
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      links    = ["wordpress"]
      volumes  = [
        {
          name = "nginx-conf"
          containerPath = "/etc/nginx/conf.d"
          readOnly = true
        }
      ]
    },
    {
      name      = "wordpress"
      image     = "wordpress:fpm-alpine"
      essential = true
      memory    = var.task_memory
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
          sourceVolume  = "wordpress-data"
          containerPath = "/var/www/html"
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
    name = "wordpress-data"
    efs_volume_configuration {
      file_system_id = var.efs_filesystem_id
      root_directory = "/"
    }
  }

  tags = {
    Name = "wordpress-task"
  }
}

resource "aws_ecs_service" "wordpress" {
  name            = "wordpress"
  cluster         = aws_ecs_cluster.wordpress.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "wordpress"
    container_port   = 80
  }
}
