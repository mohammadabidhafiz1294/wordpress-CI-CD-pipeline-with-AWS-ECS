# Root Terraform configuration for WordPress ECS project
# Architecture: ECS Primary + Spot + EC2 Admin with shared EFS

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Module
module "vpc" {
  source             = "./modules/vpc"
  vpc_cidr           = var.vpc_cidr
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
  availability_zones = var.availability_zones
}

# Security Module
module "security" {
  source   = "./modules/security"
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr
}

# IAM Module
module "iam" {
  source = "./modules/iam"
}

# EFS Module (Shared between ECS and EC2)
module "efs" {
  source                     = "./modules/efs"
  subnet_ids                 = module.vpc.private_subnets
  vpc_id                     = module.vpc.vpc_id
  allowed_security_group_ids = [module.security.ecs_security_group_id, module.security.ec2_admin_security_group_id]
}

# RDS Module
module "rds" {
  source                     = "./modules/rds"
  database_name              = var.database_name
  database_user              = var.database_user
  database_password          = var.database_password
  private_subnet_ids         = module.vpc.private_subnets
  database_security_group_id = module.security.database_security_group_id
  instance_class             = var.db_instance_class
}

# ECR Module
module "ecr" {
  source          = "./modules/ecr"
  repository_name = var.repository_name
}

# ALB Module with host-based routing
module "alb" {
  source                = "./modules/alb"
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnets
  alb_security_group_id = module.security.alb_public_security_group_id
  public_domain_name    = var.domain_name
  admin_domain_name     = "admin.${var.domain_name}"
}

# ECS Primary (On-demand)
module "ecs_primary" {
  source                = "./modules/ecs"
  service_name          = "wordpress-primary"
  environment           = "production"
  capacity_provider     = "FARGATE"
  cluster_name          = "wordpress-cluster"
  subnet_ids            = module.vpc.private_subnets
  security_group_ids    = [module.security.ecs_security_group_id]
  vpc_id                = module.vpc.vpc_id
  ecs_security_group_id = module.security.ecs_security_group_id
  private_subnet_ids    = module.vpc.private_subnets
  target_group_arn      = module.alb.blue_target_group_arn
  execution_role_arn    = module.iam.execution_role_arn
  task_role_arn         = module.iam.task_role_arn
  wordpress_image       = "${module.ecr.repository_url}:latest"
  nginx_image           = "nginx:1.25-alpine"
  database_endpoint     = module.rds.endpoint
  database_name         = var.database_name
  database_user         = var.database_user
  database_password     = var.database_password
  task_cpu              = var.task_cpu
  task_memory           = var.task_memory
  wordpress_memory      = var.wordpress_memory
  efs_filesystem_id     = module.efs.efs_id
  aws_region            = var.aws_region
  service_desired_count = 1
}

# ECS Backup (Spot)
module "ecs_backup" {
  source                = "./modules/ecs"
  service_name          = "wordpress-backup"
  environment           = "production"
  capacity_provider     = "FARGATE_SPOT"
  cluster_name          = "wordpress-cluster"
  subnet_ids            = module.vpc.private_subnets
  security_group_ids    = [module.security.ecs_security_group_id]
  vpc_id                = module.vpc.vpc_id
  ecs_security_group_id = module.security.ecs_security_group_id
  private_subnet_ids    = module.vpc.private_subnets
  target_group_arn      = module.alb.blue_target_group_arn
  execution_role_arn    = module.iam.execution_role_arn
  task_role_arn         = module.iam.task_role_arn
  wordpress_image       = "${module.ecr.repository_url}:latest"
  nginx_image           = "nginx:1.25-alpine"
  database_endpoint     = module.rds.endpoint
  database_name         = var.database_name
  database_user         = var.database_user
  database_password     = var.database_password
  task_cpu              = var.task_cpu
  task_memory           = var.task_memory
  wordpress_memory      = var.wordpress_memory
  efs_filesystem_id     = module.efs.efs_id
  aws_region            = var.aws_region
  service_desired_count = 1
}

# EC2 Admin Module
module "ec2_admin" {
  source            = "./modules/ec2-admin"
  instance_type     = var.ec2_instance_type
  subnet_id         = module.vpc.private_subnets[0]
  vpc_id            = module.vpc.vpc_id
  security_group_id = module.security.ec2_admin_security_group_id
  efs_dns_name      = module.efs.efs_dns_name
  admin_domain_name = "admin.${var.domain_name}"
  database_password = var.database_password
  database_endpoint = module.rds.endpoint
}

# Route53 Module
module "route53" {
  source       = "./modules/route53"
  domain_name  = var.domain_name
  alb_dns_name = module.alb.alb_dns_name
  alb_zone_id  = module.alb.alb_zone_id
}

# CodeDeploy Module for Blue-Green Deployment
module "codedeploy" {
  source                           = "./modules/codedeploy"
  application_name                 = "wordpress-ecs"
  deployment_group_name            = "wordpress-production"
  deployment_config_name           = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
  ecs_cluster_name                 = "wordpress-cluster"
  ecs_service_name                 = "wordpress-primary"
  alb_listener_arn                 = module.alb.listener_arn
  blue_target_group_name           = module.alb.blue_target_group_name
  green_target_group_name          = module.alb.green_target_group_name
  termination_wait_time_in_minutes = 60
  environment                      = "production"
}
