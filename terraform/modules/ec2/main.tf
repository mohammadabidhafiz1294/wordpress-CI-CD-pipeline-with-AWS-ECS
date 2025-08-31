resource "aws_instance" "main" {
	ami           = var.ami_id
	instance_type = var.instance_type
	subnet_id     = var.subnet_id
	vpc_security_group_ids = var.security_group_ids
}

resource "aws_instance" "bastion" {
  ami           = var.ami_id
  instance_type = "t3.micro"
  subnet_id     = var.public_subnet_id
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = {
    Name = "wordpress-bastion"
  }
}

resource "aws_security_group" "bastion" {
  name        = "wordpress-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-bastion-sg"
  }
}
