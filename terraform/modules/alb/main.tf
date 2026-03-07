resource "aws_lb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "wordpress-alb"
  }
}

# Blue Target Group (Current Production)
resource "aws_lb_target_group" "blue" {
  name        = "wordpress-blue-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

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
    Name = "wordpress-blue-tg"
  }
}

# Green Target Group (New Deployment)
resource "aws_lb_target_group" "green" {
  name        = "wordpress-green-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

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
    Name = "wordpress-green-tg"
  }
}

# EC2 Admin Target Group (Unchanged)
resource "aws_lb_target_group" "ec2_admin" {
  name        = "wordpress-ec2-admin-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/wp-admin/admin-ajax.php"
    matcher             = "200"
  }

  tags = {
    Name = "wordpress-ec2-admin-tg"
  }
}

# Production Listener (Default routing)
resource "aws_lb_listener" "wordpress" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# Listener Rule: Public Site
resource "aws_lb_listener_rule" "public_site" {
  listener_arn = aws_lb_listener.wordpress.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    host_header {
      values = [var.public_domain_name]
    }
  }
}

# Listener Rule: WWW Redirect
resource "aws_lb_listener_rule" "www_redirect" {
  listener_arn = aws_lb_listener.wordpress.arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    host_header {
      values = ["www.${var.public_domain_name}"]
    }
  }
}

# Listener Rule: Admin Site
resource "aws_lb_listener_rule" "admin_site" {
  listener_arn = aws_lb_listener.wordpress.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2_admin.arn
  }

  condition {
    host_header {
      values = [var.admin_domain_name]
    }
  }
}
