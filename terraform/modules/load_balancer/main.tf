resource "aws_lb" "main" {
	name               = "main-lb"
	internal           = false
	load_balancer_type = "application"
	subnets            = var.subnet_ids
	security_groups    = var.security_group_ids
}
