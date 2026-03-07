# Terraform Documentation

This document provides comprehensive documentation for the WordPress ECS infrastructure Terraform configuration.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Module Structure](#module-structure)
3. [Root Configuration](#root-configuration)
4. [Module Details](#module-details)
5. [Variables Reference](#variables-reference)
6. [Outputs Reference](#outputs-reference)
7. [Usage Guide](#usage-guide)
8. [Security Features](#security-features)

---

## Project Overview

This Terraform project deploys a highly available WordPress infrastructure on AWS with the following architecture:

- **ECS Fargate** (Primary - On Demand)
- **ECS Fargate Spot** (Backup - Cost Optimized)
- **EC2 Admin Server** (t3.micro for wp-admin)
- **Application Load Balancer** (Host-based routing)
- **EFS** (Shared wp-content storage)
- **RDS MySQL** (Database)
- **Route53** (DNS management)

### Cost Estimate

| Resource | Monthly Cost |
|----------|--------------|
| ECS Primary (FARGATE) | ~$8-10 |
| ECS Backup (FARGATE_SPOT) | ~$2-3 |
| RDS t3.micro + backups | ~$14 |
| EFS | ~$3 |
| EC2 t3.micro | ~$8 |
| ALB | ~$16 |
| **Total** | **~$51-54/month** |

---

## Module Structure

```
terraform/
├── main.tf                 # Root module - orchestrates all submodules
├── variables.tf           # Root variables
├── outputs.tf             # Root outputs
├── terraform.tfvars.example  # Example configuration
└── modules/
    ├── vpc/              # VPC and subnets
    ├── security/         # Security groups
    ├── iam/              # IAM roles
    ├── efs/              # Elastic File System
    ├── rds/              # RDS MySQL database
    ├── ecr/              # ECR Docker repository
    ├── alb/              # Application Load Balancer
    ├── ecs/              # ECS Fargate cluster and services
    ├── ec2-admin/        # EC2 Admin server
    └── route53/          # DNS configuration
```

---

## Root Configuration

### main.tf

The root `main.tf` orchestrates the deployment by calling all submodules in the correct order:

```hcl
# Execution order:
1. VPC (provides networking)
2. Security (depends on VPC)
3. IAM (provides roles)
4. EFS (depends on VPC, Security)
5. RDS (depends on VPC, Security)
6. ECR (AWS-wide resource)
7. ALB (depends on VPC, Security)
8. ECS Primary (depends on all above)
9. ECS Backup (depends on all above)
10. EC2 Admin (depends on EFS, Security)
11. Route53 (depends on ALB)
```

### Key Features

- **Dual ECS Services**: Primary (FARGATE) and Backup (FARGATE_SPOT)
- **Host-based Routing**: Single ALB routes based on domain
- **Shared Storage**: EFS mounted to both ECS and EC2
- **Security Groups**: Proper isolation between components

---

## Module Details

### 1. VPC Module (`modules/vpc/`)

Creates the Virtual Private Cloud networking infrastructure.

**Files:**
- `main.tf` - VPC, subnets, route tables
- `variables.tf` - Configuration variables
- `outputs.tf` - VPC IDs, subnet IDs

**Variables:**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vpc_cidr` | string | `"11.0.0.0/16"` | VPC CIDR block |
| `public_subnets` | list(string) | `["11.0.1.0/24", "11.0.2.0/24"]` | Public subnet CIDRs |
| `private_subnets` | list(string) | `["11.0.3.0/24", "11.0.4.0/24"]` | Private subnet CIDRs |
| `availability_zones` | list(string) | `["us-east-1a", "us-east-1b"]` | AWS AZs |

**Outputs:**

| Output | Description |
|--------|-------------|
| `vpc_id` | ID of the VPC |
| `public_subnets` | List of public subnet IDs |
| `private_subnets` | List of private subnet IDs |

---

### 2. Security Module (`modules/security/`)

Creates security groups for all components.

**Files:**
- `main.tf` - Security group resources
- `variables.tf` - Configuration variables
- `outputs.tf` - Security group IDs

**Security Groups Created:**

| Security Group | Purpose |
|---------------|---------|
| `alb_public` | Public ALB (HTTP/HTTPS from 0.0.0.0/0) |
| `alb_internal` | Internal ALB for admin (VPC only) |
| `ecs` | ECS tasks (from ALB) |
| `ec2_admin` | EC2 Admin (from Internal ALB) |
| `database` | RDS MySQL (from ECS, EC2) |

**Variables:**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vpc_id` | string | - | VPC ID (required) |
| `vpc_cidr` | string | `"11.0.0.0/16"` | VPC CIDR for internal rules |

---

### 3. IAM Module (`modules/iam/`)

Creates IAM roles for ECS tasks.

**Files:**
- `main.tf` - IAM role resources
- `variables.tf` - Configuration variables
- `outputs.tf` - Role ARNs

**IAM Roles Created:**

| Role | Purpose |
|------|---------|
| `ecs_execution_role` | ECS task execution (pull images, CloudWatch logs) |
| `ecs_task_role` | ECS task access to AWS resources |

**Variables:**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `execution_role_name` | string | `"wordpress-ecs-execution-role"` | Execution role name |
| `task_role_name` | string | `"wordpress-ecs-task-role"` | Task role name |

**Outputs:**

| Output | Description |
|--------|-------------|
| `execution_role_arn` | ARN of ECS execution role |
| `task_role_arn` | ARN of ECS task role |

---

### 4. EFS Module (`modules/efs/`)

Creates Elastic File System for shared wp-content storage.

**Files:**
- `main.tf` - EFS filesystem and mount targets
- `variables.tf` - Configuration variables
- `outputs.tf` - EFS IDs and DNS names

**Security Features:**
- ✅ Encryption at rest enabled
- ✅ Transit encryption enabled (in ECS mount)
- ✅ Access point for wp-content isolation

**Variables:**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `subnet_ids` | list(string) | - | Subnet IDs for mount targets (required) |
| `vpc_id` | string | - | VPC ID (required) |
| `allowed_security_group_ids` | list(string) | - | Security groups allowed access (required) |
| `kms_key_id` | string | `""` | KMS key for encryption (optional) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `efs_id` | ID of the EFS filesystem |
| `efs_dns_name` | DNS name for EFS mount |
| `efs_security_group_id` | Security group ID for EFS |
| `access_point_id` | EFS access point ID |

---

### 5. RDS Module (`modules/rds/`)

Creates RDS MySQL database for WordPress.

**Files:**
- `main.tf` - RDS instance
- `variables.tf` - Configuration variables
- `outputs.tf` - Database endpoint

**Features:**
- Multi-AZ: No (budget optimization)
- Automated backups: Enabled (7 days retention)
- Encryption: Enabled at rest

**Variables:**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `database_name` | string | `"wordpress"` | Database name |
| `database_user` | string | `"wordpress"` | Database username |
| `database_password` | string | - | Database password (sensitive) |
| `private_subnet_ids` | list(string) | - | Subnet IDs for RDS (required) |
| `database_security_group_id` | string | - | Security group ID (required) |
| `instance_class` | string | `"db.t3.micro"` | RDS instance class |

**Outputs:**

| Output | Description |
|--------|-------------|
| `endpoint` | RDS endpoint address |
| `port` | RDS port (3306) |

---

### 6. ECR Module (`modules/ecr/`)

Creates ECR repository for Docker images.

**Files:**
- `main.tf` - ECR repository
- `variables.tf` - Configuration variables
- `outputs.tf` - Repository URL

**Features:**
- Image scanning on push enabled
- Lifecycle policy (keep last 5 images)
- Tag mutability: MUTABLE

**Variables:**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `repository_name` | string | `"wordpress"` | ECR repository name |

**Outputs:**

| Output | Description |
|--------|-------------|
| `repository_url` | Full ECR repository URL |

---

### 7. ALB Module (`modules/alb/`)

Creates Application Load Balancer with host-based routing.

**Files:**
- `main.tf` - ALB, target groups, listener rules
- `variables.tf` - Configuration variables
- `outputs.tf` - ALB DNS names

**Routing Rules:**

| Priority | Host | Target |
|----------|------|--------|
| 100 | `yourdomain.com` | ECS Primary |
| 50 | `www.yourdomain.com` | ECS Primary |
| 200 | `admin.yourdomain.com` | EC2 Admin |

**Variables:**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vpc_id` | string | - | VPC ID (required) |
| `public_subnet_ids` | list(string) | - | Public subnet IDs (required) |
| `alb_security_group_id` | string | - | Security group ID (required) |
| `public_domain_name` | string | - | Public domain (required) |
| `admin_domain_name` | string | - | Admin domain (required) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `alb_dns_name` | ALB DNS name |
| `alb_zone_id` | ALB hosted zone ID |
| `ecs_target_group_arn` | ECS target group ARN |
| `ec2_admin_target_group_arn` | EC2 admin target group ARN |

---

### 8. ECS Module (`modules/ecs/`)

Creates ECS Fargate cluster and services.

**Files:**
- `main.tf` - Cluster, task definitions, services
- `variables.tf` - Configuration variables
- `outputs.tf` - Service information

**Features:**
- Capacity providers: FARGATE and FARGATE_SPOT
- Dual container setup: Nginx + WordPress PHP-FPM
- EFS mount for wp-content
- CloudWatch logging

**Container Configuration:**

| Container | Image | Port | Memory |
|-----------|-------|------|--------|
| nginx | nginx:1.25-alpine | 80 | Variable |
| wordpress | wordpress:6.4.x-php8.2-fpm-alpine | 9000 | Variable |

**Variables:**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `service_name` | string | `"wordpress"` | Service name |
| `environment` | string | `"production"` | Environment |
| `capacity_provider` | string | `"FARGATE"` | FARGATE or FARGATE_SPOT |
| `cluster_name` | string | `"wordpress-cluster"` | Cluster name |
| `subnet_ids` | list(string) | - | Subnet IDs (required) |
| `security_group_ids` | list(string) | - | Security group IDs (required) |
| `vpc_id` | string | - | VPC ID (required) |
| `ecs_security_group_id` | string | - | ECS security group (required) |
| `target_group_arn` | string | - | ALB target group ARN |
| `execution_role_arn` | string | - | ECS execution role ARN |
| `task_role_arn` | string | - | ECS task role ARN |
| `wordpress_image` | string | - | WordPress image URI |
| `nginx_image` | string | `"nginx:1.25-alpine"` | Nginx image |
| `database_endpoint` | string | - | RDS endpoint |
| `database_name` | string | `"wordpress"` | Database name |
| `database_user` | string | `"wordpress"` | Database user |
| `database_password` | string | - | Database password (sensitive) |
| `task_cpu` | number | `256` | CPU units |
| `task_memory` | number | `512` | Memory (MB) |
| `wordpress_memory` | number | `256` | WordPress container memory |
| `efs_filesystem_id` | string | - | EFS filesystem ID |
| `aws_region` | string | - | AWS region |
| `service_desired_count` | number | `1` | Number of tasks |

**Outputs:**

| Output | Description |
|--------|-------------|
| `cluster_id` | ECS cluster ID |
| `cluster_name` | ECS cluster name |
| `service_name` | ECS service name |
| `target_group_arn` | Target group ARN |

---

### 9. EC2 Admin Module (`modules/ec2-admin/`)

Creates EC2 instance for WordPress admin.

**Files:**
- `main.tf` - EC2 instance, IAM profile, target group
- `variables.tf` - Configuration variables
- `outputs.tf` - Instance information
- `user-data.sh` - Initialization script

**Features:**
- Instance Type: t3.micro
- IAM profile with SSM and EFS access
- Auto-mounts EFS wp-content
- Installs WordPress via WP-CLI

**Variables:**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ami_id` | string | See code | Amazon Linux 2023 AMI |
| `instance_type` | string | `"t3.micro"` | EC2 instance type |
| `subnet_id` | string | - | Subnet ID (required) |
| `vpc_id` | string | - | VPC ID (required) |
| `security_group_id` | string | - | Security group ID (required) |
| `efs_dns_name` | string | - | EFS DNS name (required) |
| `admin_domain_name` | string | - | Admin domain name (required) |
| `database_password` | string | - | Database password (sensitive) |
| `database_endpoint` | string | - | RDS endpoint |

**Outputs:**

| Output | Description |
|--------|-------------|
| `instance_id` | EC2 instance ID |
| `instance_private_ip` | Private IP address |
| `target_group_arn` | Target group ARN |
| `instance_profile_name` | IAM instance profile name |

---

### 10. Route53 Module (`modules/route53/`)

Creates DNS records for WordPress.

**Files:**
- `main.tf` - Route53 hosted zone and records
- `variables.tf` - Configuration variables
- `outputs.tf` - Zone information

**DNS Records:**

| Record | Type | Target |
|--------|------|--------|
| `yourdomain.com` | A | ALB (alias) |
| `www.yourdomain.com` | A | ALB (alias) |
| `admin.yourdomain.com` | A | ALB (alias) |

**Variables:**

| Variable | Type | Description |
|----------|------|-------------|
| `domain_name` | string | Domain name (required) |
| `alb_dns_name` | string | ALB DNS name (required) |
| `alb_zone_id` | string | ALB zone ID (required) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `zone_id` | Route53 hosted zone ID |

---

## Variables Reference

### Root Variables (terraform/variables.tf)

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `aws_region` | string | `"us-east-1"` | No | AWS region |
| `vpc_cidr` | string | `"11.0.0.0/16"` | No | VPC CIDR block |
| `public_subnets` | list(string) | `[...]` | No | Public subnet CIDRs |
| `private_subnets` | list(string) | `[...]` | No | Private subnet CIDRs |
| `availability_zones` | list(string) | `[...]` | No | AWS availability zones |
| `domain_name` | string | - | **Yes** | WordPress domain name |
| `database_password` | string | - | **Yes** | RDS password (sensitive) |
| `database_name` | string | `"wordpress"` | No | Database name |
| `database_user` | string | `"wordpress"` | No | Database username |
| `db_instance_class` | string | `"db.t3.micro"` | No | RDS instance class |
| `repository_name` | string | `"wordpress"` | No | ECR repository name |
| `task_cpu` | number | `256` | No | ECS task CPU units |
| `task_memory` | number | `512` | No | ECS task memory (MB) |
| `wordpress_memory` | number | `256` | No | WordPress container memory |
| `nginx_memory` | number | `256` | No | Nginx container memory |
| `ec2_instance_type` | string | `"t3.micro"` | No | EC2 admin instance type |

---

## Outputs Reference

### Root Outputs (terraform/outputs.tf)

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `public_subnet_ids` | Public subnet IDs |
| `private_subnet_ids` | Private subnet IDs |
| `alb_dns_name` | ALB DNS name |
| `public_url` | WordPress public URL |
| `admin_url` | WordPress admin URL |
| `ecr_repository_url` | ECR repository URL |
| `rds_endpoint` | RDS endpoint |
| `ecs_cluster_name` | ECS cluster name |
| `ecs_primary_service_name` | Primary ECS service name |
| `ecs_backup_service_name` | Backup ECS service name |
| `efs_dns_name` | EFS DNS name |
| `ec2_admin_instance_id` | EC2 admin instance ID |

---

## Usage Guide

### 1. Configuration

Copy the example tfvars file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` with your values:

```hcl
# Required
aws_region        = "us-east-1"
domain_name       = "yourdomain.com"
database_password = "your-secure-password-here"

# Optional (with defaults)
vpc_cidr        = "11.0.0.0/16"
public_subnets  = ["11.0.1.0/24", "11.0.2.0/24"]
private_subnets = ["11.0.3.0/24", "11.0.4.0/24"]
```

### 2. Initialize Terraform

```bash
cd terraform
terraform init
```

### 3. Plan Deployment

```bash
terraform plan
```

### 4. Apply Configuration

```bash
terraform apply
```

### 5. Configure DNS

After deployment, update your domain's nameservers to the Route53 nameservers provided in the outputs.

---

## Security Features

### Encryption

| Feature | Status | Details |
|---------|--------|---------|
| EFS at Rest | ✅ Enabled | AWS-managed KMS key |
| EFS Transit | ✅ Enabled | TLS 1.2+ |
| RDS at Rest | ✅ Enabled | AWS-managed KMS key |
| RDS Transit | ✅ Enforced | Require SSL connection |
| ALB to Target | ✅ HTTPS | SSL/TLS termination |

### Network Security

| Feature | Implementation |
|---------|----------------|
| VPC Isolation | Separate public/private subnets |
| Security Groups | Least privilege access |
| Internal ALB | Admin only accessible within VPC |
| No Public EC2 | Admin server in private subnet |

### Access Control

| Feature | Implementation |
|---------|----------------|
| IAM Roles | Task execution and task roles |
| SSM Access | EC2 admin for instance management |
| No SSH | SSM Session Manager for access |

---

## Troubleshooting

### Common Issues

1. **EFS Mount Issues**
   - Check security group allows NFS (port 2049)
   - Verify subnet IDs are correct
   - Check EFS lifecycle policy

2. **ECS Deployment Fails**
   - Verify ECR image exists
   - Check task definition has correct memory/CPU
   - Review CloudWatch logs

3. **ALB Health Check Failures**
   - Check security groups allow traffic
   - Verify target group port configuration
   - Review health check path

4. **Database Connection**
   - Verify RDS is in same VPC
   - Check database security group allows ECS/EC2
   - Confirm credentials are correct

---

## Maintenance

### Updating WordPress

1. Push new Docker image via CI/CD
2. GitHub Actions automatically deploys to both services

### Scaling

| Component | Scaling Method |
|-----------|----------------|
| ECS Tasks | Update `service_desired_count` variable |
| RDS | Change `db_instance_class` |
| EC2 | Change `ec2_instance_type` |

### Backup & Recovery

- RDS: Automated daily backups (7-day retention)
- EFS: Consider EFS backup solutions for critical data

---

## License

This project is licensed under the MIT License.
