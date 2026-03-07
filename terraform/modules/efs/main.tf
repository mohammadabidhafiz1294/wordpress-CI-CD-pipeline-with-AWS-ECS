resource "aws_efs_file_system" "wordpress" {
  creation_token = "wordpress-efs"
  encrypted      = true
  kms_key_id     = var.kms_key_id

  tags = {
    Name = "wordpress-efs"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "wordpress-efs-sg"
  description = "Security group for WordPress EFS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-efs-sg"
  }
}

resource "aws_efs_access_point" "wp_content" {
  file_system_id = aws_efs_file_system.wordpress.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/wp-content"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "wordpress-wp-content-access-point"
  }
}
