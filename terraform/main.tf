// Root Terraform configuration for Wordpress ECS project
// Modules: vpc, ecs, rds, ecr, load_balancer

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

module "vpc" {
  source          = "./modules/vpc"
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  availability_zones = var.availability_zones
}

module "security" {
  source = "./modules/security"
  vpc_id = module.vpc.vpc_id
}

module "efs" {
  source                = "./modules/efs"
  private_subnet_ids    = module.vpc.private_subnet_ids
  vpc_id               = module.vpc.vpc_id
  ecs_security_group_id = module.security.ecs_security_group_id
}

module "rds" {
  source                    = "./modules/rds"
  database_name            = var.database_name
  database_user            = var.database_user
  database_password        = var.database_password
  private_subnet_ids       = module.vpc.private_subnet_ids
  database_security_group_id = module.security.database_security_group_id
  instance_class           = var.db_instance_class
}

module "alb" {
  source               = "./modules/alb"
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
}

module "ecr" {
  source          = "./modules/ecr"
  repository_name = var.repository_name
}

module "ecs" {
  source                = "./modules/ecs"
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  ecs_security_group_id = module.security.ecs_security_group_id
  target_group_arn     = module.alb.target_group_arn
  execution_role_arn   = module.iam.execution_role_arn
  task_role_arn        = module.iam.task_role_arn
  wordpress_image      = "${module.ecr.repository_url}:latest"
  database_endpoint    = module.rds.endpoint
  database_name        = var.database_name
  database_user        = var.database_user
  database_password    = var.database_password
  task_cpu            = var.task_cpu
  task_memory         = var.task_memory
}

module "route53" {
  source       = "./modules/route53"
  domain_name  = var.domain_name
  alb_dns_name = module.alb.alb_dns_name
  alb_zone_id  = module.alb.alb_zone_id
}
