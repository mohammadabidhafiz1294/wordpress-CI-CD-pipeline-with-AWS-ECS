resource "aws_instance" "wordpress_admin" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [var.security_group_id]

  key_name = var.key_name

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    efs_dns_name      = var.efs_dns_name
    admin_domain_name = var.admin_domain_name
    db_password       = var.database_password
    db_endpoint       = var.database_endpoint
  }))

  iam_instance_profile = aws_iam_instance_profile.ec2_admin.name

  tags = {
    Name        = "wordpress-admin-server"
    Environment = var.environment
    Role        = "wordpress-admin"
  }
}

resource "aws_iam_instance_profile" "ec2_admin" {
  name = "wordpress-admin-instance-profile"

  role = aws_iam_role.ec2_admin.name
}

resource "aws_iam_role" "ec2_admin" {
  name = "wordpress-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_admin_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_admin.name
}

resource "aws_iam_role_policy_attachment" "ec2_admin_efs" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientFullAccess"
  role       = aws_iam_role.ec2_admin.name
}

resource "aws_lb_target_group" "ec2_admin" {
  name     = "wordpress-admin-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

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
    Name = "wordpress-admin-target-group"
  }
}

resource "aws_lb_target_group_attachment" "ec2_admin" {
  target_group_arn = aws_lb_target_group.ec2_admin.arn
  target_id        = aws_instance.wordpress_admin.id
  port             = 80
}
