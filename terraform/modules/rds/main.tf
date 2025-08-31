resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "wordpress" {
  identifier           = "wordpress"
  allocated_storage    = 20
  storage_type        = "gp2"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = var.instance_class
  db_name             = var.database_name
  username            = var.database_user
  password            = var.database_password
  skip_final_snapshot = true

  vpc_security_group_ids = [var.database_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name

  tags = {
    Name = "wordpress-database"
  }
}
