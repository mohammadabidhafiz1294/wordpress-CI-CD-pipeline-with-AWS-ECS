resource "aws_codedeploy_app" "wordpress" {
  name             = var.application_name
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "wordpress" {
  app_name               = aws_codedeploy_app.wordpress.name
  deployment_group_name  = var.deployment_group_name
  deployment_config_name = var.deployment_config_name

  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = var.ecs_service_name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.alb_listener_arn]
      }

      target_group {
        name = var.blue_target_group_name
      }

      target_group {
        name = var.green_target_group_name
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_WARNING"]
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  service_role_arn = aws_iam_role.codedeploy.arn

  tags = {
    Name        = "${var.deployment_group_name}-dg"
    Environment = var.environment
  }
}

resource "aws_iam_role" "codedeploy" {
  name = "wordpress-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
  role       = aws_iam_role.codedeploy.name
}

resource "aws_iam_role_policy_attachment" "codedeploy_alb" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRoleForElasticLoadBalancing"
  role       = aws_iam_role.codedeploy.name
}

resource "aws_sns_topic" "codedeploy" {
  name = "${var.application_name}-notifications"
}
