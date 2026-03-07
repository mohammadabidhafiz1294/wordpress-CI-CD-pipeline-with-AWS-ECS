# WordPress CI/CD Pipeline on AWS ECS

[![AWS](https://img.shields.io/badge/AWS-ECS_Fargate-FF9900?style=flat&logo=amazon-aws)](https://aws.amazon.com/ecs/)
[![Terraform](https://img.shields.io/badge/Terraform-7B4BC9?style=flat&logo=terraform)](https://www.terraform.io/)
[![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker)](https://www.docker.com/)
[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=github-actions)](https://github.com/features/actions)
[![CI/CD](https://img.shields.io/badge/CI/CD-Blue--Green_Deployment-00C7B7?style=flat)](https://aws.amazon.com/codedeploy/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A production-ready **WordPress deployment** on AWS ECS Fargate with a complete **CI/CD pipeline** using GitHub Actions and blue-green deployment strategy. Infrastructure provisioned with Terraform.

## 🚀 Key Features

| Feature | Description |
|---------|-------------|
| **Blue-Green Deployment** | Zero-downtime deployments using AWS CodeDeploy |
| **OIDC Authentication** | Secure AWS access without long-lived credentials |
| **Shared EFS Storage** | Persistent WordPress content across ECS and EC2 |
| **Host-based Routing** | Single ALB routes traffic based on domain |
| **Auto-scaling** | ECS Fargate with on-demand and spot capacity |
| **Infrastructure as Code** | Fully modular Terraform codebase |

## 🏗️ Architecture

![Architecture Diagram](./wordpress-pipeline-CICD.pdf)

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                  │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        VPC (10.0.0.0/16)                        │   │
│  │                                                                  │   │
│  │  ┌────────────────────┐        ┌────────────────────────────┐  │   │
│  │  │  Public Subnets   │        │     Private Subnets        │  │   │
│  │  │  10.0.1.0/24 (AZ1)│        │  10.0.3.0/24 (AZ1)        │  │   │
│  │  │  10.0.2.0/24 (AZ2)│        │  10.0.4.0/24 (AZ2)        │  │   │
│  │  └─────────┬──────────┘        └─────────────┬─────────────┘  │   │
│  │            │                                 │                │   │
│  │            ▼                                 ▼                │   │
│  │  ┌────────────────────┐             ┌────────────────────┐    │   │
│  │  │  Internet Gateway │             │   NAT Gateway     │    │   │
│  │  └────────────────────┘             └────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Public Subnet Components                    │   │
│  │                                                                  │   │
│  │   ┌──────────────────┐                                          │   │
│  │   │  Application    │                                          │   │
│  │   │  Load Balancer  │◄────── Host-based Routing               │   │
│  │   │  (Single ALB)   │         • domain.com → ECS              │   │
│  │   └────────┬─────────┘         • admin.domain.com → EC2       │   │
│  │            │                                                    │   │
│  │            ▼                                                    │   │
│  │   ┌──────────────────┐   ┌──────────────────┐   ┌────────────┐ │   │
│  │   │  Target Group   │   │  Target Group   │   │  Target    │ │   │
│  │   │  (ECS Blue)     │   │  (ECS Green)    │   │  Group     │ │   │
│  │   └──────────────────┘   └──────────────────┘   │  (EC2)     │ │   │
│  │                                                └────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Private Subnet Components                   │   │
│  │                                                                  │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐          │   │
│  │  │ECS Prim │  │ECS Spot │  │  RDS    │  │   EFS   │          │   │
│  │  │FARGATE  │  │FARGATE_ │  │ MySQL   │  │  (wp-   │          │   │
│  │  │(nginx+  │  │ SPOT    │  │Database │  │ content)│          │   │
│  │  │ PHP-FPM)│  │(nginx+  │  │         │  │         │          │   │
│  │  │         │  │ PHP-FPM)│  │         │  │         │          │   │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘          │   │
│  │       │            │            │            │                │   │
│  │       └────────────┴────────────┴────────────┘                │   │
│  │                         │                                      │   │
│  │                         ▼                                      │   │
│  │               ┌──────────────────┐                             │   │
│  │               │   EC2 Admin     │                             │   │
│  │               │   (t3.micro)    │                             │   │
│  │               └──────────────────┘                             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │
                                    ▼
                            ┌───────────────┐
                            │    Internet   │
                            │   (Users)     │
                            └───────────────┘
```

## 📁 Project Structure

```
.
├── .github/
│   └── workflows/
│       └── wordpress-ci-cd.yml     # GitHub Actions CI/CD workflow
├── docker/
│   └── wordpress-fpm/
│       ├── Dockerfile               # WordPress + PHP-FPM container
│       └── nginx.conf               # Nginx reverse proxy config
├── terraform/
│   ├── main.tf                      # Root Terraform configuration
│   ├── variables.tf                 # Input variables
│   ├── outputs.tf                  # Output values
│   ├── terraform.tfvars.example    # Example variables file
│   ├── ARCHITECTURE.md             # Detailed architecture docs
│   ├── CODE_DEPLOY.md              # Deployment configuration
│   ├── TERRAFORM.md                # Terraform best practices
│   └── modules/                     # Modular Terraform components
│       ├── vpc/                     # VPC networking
│       ├── security/                # Security groups
│       ├── iam/                     # IAM roles (ECS execution/task)
│       ├── ecr/                     # ECR container registry
│       ├── efs/                     # EFS shared storage
│       ├── rds/                     # RDS MySQL database
│       ├── alb/                     # Application Load Balancer
│       ├── ecs/                     # ECS Fargate cluster
│       ├── ec2-admin/               # EC2 admin server
│       ├── route53/                 # DNS records
│       └── codedeploy/              # CodeDeploy configuration
├── wordpress/
│   └── README.md                    # WordPress configuration notes
├── wordpress-pipeline-CICD.pdf     # Architecture diagram (PDF)
├── LICENSE
└── README.md                        # This file
```

## 🔄 CI/CD Pipeline

### Workflow Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CI/CD PIPELINE FLOW                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  GitHub Repository                                                      │
│       │                                                                  │
│       │ Push to main branch (wordpress/ or docker/ changed)            │
│       ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │              GitHub Actions Triggered                          │   │
│  │                                                                  │   │
│  │  Job: build-and-push                                            │   │
│  │  ├── Checkout code                                              │   │
│  │  ├── Configure AWS credentials (OIDC)                           │   │
│  │  ├── Login to ECR                                               │   │
│  │  ├── Build Docker image (with cache)                           │   │
│  │  │   ├── Base: wordpress:6.4.3-php8.2-fpm-alpine              │   │
│  │  │   └── Custom nginx configuration                            │   │
│  │  └── Push to ECR (tagged with SHA + latest)                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                  │
│       │ New Image Tag                                                 │
│       ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │              Job: create-deployment                             │   │
│  │                                                                  │   │
│  │  ├── Get current task definition                                │   │
│  │  ├── Create new task definition (update image)                 │   │
│  │  ├── Register new revision                                      │   │
│  │  ├── Create CodeDeploy deployment (Blue-Green)                │   │
│  │  └── Wait for deployment completion                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                  │
│       │ Success/Failure                                               │
│       ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │              Job: verify + notify                               │   │
│  │                                                                  │   │
│  │  ├── Verify ECS service status                                  │   │
│  │  ├── Check ALB target group health                             │   │
│  │  ├── Send notification (success/failure)                        │   │
│  │  └── Auto-rollback on failure                                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Pipeline Features

- **OIDC Authentication**: Uses AWS IAM OpenID Connect for secure, credential-less access
- **Docker Buildx**: Multi-platform build support with GitHub Actions cache
- **Image Tagging**: Tags images with commit SHA and `latest`
- **Blue-Green Deployment**: CodeDeploy manages traffic switch
- **Health Checks**: Verifies ECS service and ALB target groups
- **Auto Rollback**: Automatically rolls back on deployment failure
- **Manual Trigger**: Can be triggered manually via GitHub Actions UI

## 🛠️ Tech Stack

| Category | Technology | Purpose |
|----------|------------|---------|
| **Cloud** | AWS | Cloud infrastructure provider |
| **Container** | ECS Fargate | Serverless container orchestration |
| **Database** | Amazon RDS MySQL | Managed database |
| **Storage** | Amazon EFS | Shared file storage |
| **Load Balancer** | Application Load Balancer | Traffic routing |
| **DNS** | Route53 | Domain management |
| **CI/CD** | GitHub Actions | Automation pipeline |
| **Deployment** | AWS CodeDeploy | Blue-green deployments |
| **IaC** | Terraform | Infrastructure provisioning |
| **Containerization** | Docker | Application packaging |

## 📋 Prerequisites

- AWS Account with appropriate permissions
- GitHub Account
- Domain name (configured in Route53)
- Terraform >= 1.0.0
- AWS CLI configured
- Docker installed locally

## 🚦 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/mohammadabidhafiz1294/wordpress-CI-CD-pipeline-with-AWS-ECS.git
cd wordpress-CI-CD-pipeline-with-AWS-ECS
```

### 2. Configure AWS Credentials

```bash
aws configure
```

### 3. Set Up GitHub Secrets

Navigate to your repository's **Settings → Secrets and variables → Actions** and add:

| Secret | Description | Example |
|--------|-------------|---------|
| `AWS_REGION` | AWS region | `us-west-2` |
| `AWS_ACCOUNT_ID` | AWS account ID | `123456789012` |
| `AWS_ROLE_ARN` | IAM role for deployment | `arn:aws:iam::...` |
| `ECR_REPOSITORY` | ECR repository name | `wordpress` |
| `ECS_CLUSTER` | ECS cluster name | `wordpress-cluster` |
| `ECS_SERVICE` | ECS service name | `wordpress-primary` |
| `DOMAIN_NAME` | Your domain | `example.com` |

### 4. Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 5. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 6. Trigger CI/CD Pipeline

Push changes to the `main` branch:

```bash
git add .
git commit -m "Deploy WordPress"
git push origin main
```

## 🔐 Security

- **OIDC Authentication**: No long-lived AWS credentials stored in GitHub
- **Least Privilege**: IAM roles with minimal required permissions
- **Private Subnets**: RDS database in private subnets
- **Security Groups**: Restrictive inbound/outbound rules
- **Secrets Management**: Database credentials via Terraform variables

## 📊 Monitoring

- **ECS Container Insights**: Container-level monitoring
- **CloudWatch Logs**: Centralized logging
- **ALB Access Logs**: Request/response logging
- **CodeDeploy**: Deployment status tracking

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing-feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👤 Author

**Mohammad Abid Hafiz**
- GitHub: [@mohammadabidhafiz1294](https://github.com/mohammadabidhafiz1294)

---

⭐️ If you found this project useful, please consider giving it a star!
