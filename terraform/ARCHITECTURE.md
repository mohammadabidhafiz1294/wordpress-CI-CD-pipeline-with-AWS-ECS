# Architecture Documentation

## Table of Contents

1. [AWS Infrastructure Architecture](#aws-infrastructure-architecture)
2. [Module Dependency Flow](#module-dependency-flow)
3. [Data Flow Diagrams](#data-flow-diagrams)
4. [Security Groups Flow](#security-groups-flow)
5. [Deployment Order](#deployment-order)
6. [CI/CD Pipeline](#cicd-pipeline)

---

## AWS Infrastructure Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    AWS Cloud                                           │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐  │
│  │                         VPC (11.0.0.0/16)                                     │  │
│  │                                                                                  │  │
│  │  ┌──────────────────────────┐         ┌──────────────────────────────┐        │  │
│  │  │   Public Subnets       │         │     Private Subnets          │        │  │
│  │  │  11.0.1.0/24 (AZ1)     │         │  11.0.3.0/24 (AZ1)          │        │  │
│  │  │  11.0.2.0/24 (AZ2)     │         │  11.0.4.0/24 (AZ2)          │        │  │
│  │  └───────────┬──────────────┘         └─────────────┬──────────────┘        │  │
│  │              │                                       │                         │  │
│  │              ▼                                       ▼                         │  │
│  │  ┌─────────────────────┐               ┌─────────────────────────────┐    │  │
│  │  │   Internet Gateway │               │       NAT Gateway           │    │  │
│  │  └─────────────────────┘               └─────────────────────────────┘    │  │
│  │                                                                                  │  │
│  └─────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐  │
│  │                        Public Subnet Components                                  │  │
│  │                                                                                  │  │
│  │   ┌─────────────────────┐                                                        │  │
│  │   │   ALB (Public)     │◄──────────────┐                                        │  │
│  │   │  Single ALB with   │               │                                        │  │
│  │   │  Host-based        │               │                                        │  │
│  │   │  Routing          │               │                                        │  │
│  │   └─────────┬──────────┘               │                                        │  │
│  │             │                          │                                        │  │
│  │             │ Host-based               │                                        │  │
│  │             │ routing                  │                                        │  │
│  │             │                          │                                        │  │
│  │             ▼                          ▼                                        │  │
│  │   ┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐  │  │
│  │   │   Target Group 1   │   │   Target Group 2   │   │   Target Group 3   │  │  │
│  │   │   (ECS Blue)      │   │   (ECS Green)     │   │   (EC2 Admin)      │  │  │
│  │   └─────────────────────┘   └─────────────────────┘   └─────────────────────┘  │  │
│  │                                                                                  │  │
│  │   Note: Single ALB with host-based routing:                                     │  │
│  │   • yourdomain.com ──────────► Blue/Green TGs (ECS)                           │  │
│  │   • admin.yourdomain.com ────► EC2 Admin TG                                   │  │
│  └─────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐  │
│  │                       Private Subnet Components                                  │  │
│  │                                                                                  │  │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐  │  │
│  │  │ ECS Primary   │  │ ECS Backup    │  │    RDS         │  │    EFS         │  │  │
│  │  │ (FARGATE)     │  │(FARGATE_SPOT) │  │   MySQL        │  │  (wp-content)  │  │  │
│  │  │ Nginx+PHP-FPM │  │ Nginx+PHP-FPM │  │  Database     │  │  Shared Storage│  │  │
│  │  └───────┬────────┘  └───────┬────────┘  └───────┬────────┘  └───────┬────────┘  │  │
│  │          │                    │                  │                  │           │  │
│  │          └────────────────────┴──────────────────┴──────────────────┘           │  │
│  │                                         │                                        │  │
│  │                                         ▼                                        │  │
│  │                               ┌─────────────────────┐                            │  │
│  │                               │   EC2 Admin        │                            │  │
│  │                               │   (t3.micro)       │                            │  │
│  │                               │   WordPress Admin  │                            │  │
│  │                               └─────────────────────┘                            │  │
│  │                                                                                  │  │
│  └─────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │
                                      ▼
                              ┌───────────────┐
                              │    Internet   │
                              │   (Users)     │
                              └───────────────┘
```

### WordPress Access Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              USER ACCESS FLOW                                       │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│   ┌─────────────┐                          ┌──────────────────────────────┐          │
│   │   User 1    │                          │        User 2 (Admin)       │          │
│   │ (Visitor)   │                          │   (Content Management)      │          │
│   └──────┬──────┘                          └─────────────┬──────────────┘          │
│          │                                              │                            │
│          │                                              │                            │
│          ▼                                              ▼                            │
│   ┌─────────────────────────────────────────────────────────────────────────┐      │
│   │                         Route53 DNS                                      │      │
│   │  ┌──────────────────┐              ┌──────────────────────────────┐     │      │
│   │  │ yourdomain.com   │              │    admin.yourdomain.com      │     │      │
│   │  └────────┬─────────┘              └──────────────┬───────────────┘     │      │
│   └───────────┼──────────────────────────────────────┼────────────────────┘      │
│               │                                      │                             │
│               ▼                                      ▼                             │
│   ┌─────────────────────────────────────────────────────────────────────────┐      │
│   │                    Application Load Balancer                             │      │
│   │                    (Single ALB with Host-based Routing)                  │      │
│   │                                                                       │      │
│   │   Host-based Routing:                                                  │      │
│   │   • yourdomain.com ──────────► Target Group: ECS (Blue/Green)        │      │
│   │   • admin.yourdomain.com ────► Target Group: EC2 Admin              │      │
│   │                                                                       │      │
│   └───────────────────────────────────┬───────────────────────────────────┘      │
│                                       │                                          │
│                    ┌──────────────────┴──────────────────┐                        │
│                    │                                     │                         │
│                    ▼                                     ▼                         │
│   ┌─────────────────────────────┐      ┌─────────────────────────────────┐        │
│   │      ECS Fargate            │      │       EC2 Admin                 │        │
│   │   ┌───────────────────┐     │      │   ┌─────────────────────────┐   │        │
│   │   │      Nginx        │     │      │   │       Nginx            │   │        │
│   │   │   (Port 80)      │     │      │   │      (Port 80)        │   │        │
│   │   └─────────┬─────────┘     │      │   └───────────┬─────────────┘   │        │
│   │             │               │      │               │                 │        │
│   │             ▼               │      │               ▼                 │        │
│   │   ┌───────────────────┐     │      │   ┌─────────────────────────┐   │        │
│   │   │   WordPress      │     │      │   │      WordPress         │   │        │
│   │   │   PHP-FPM        │     │      │   │      PHP-FPM            │   │        │
│   │   └─────────┬─────────┘     │      │   └───────────┬─────────────┘   │        │
│   │             │               │      │               │                 │        │
│   │             └───────────────┼──────┼───────────────┘                 │        │
│   │                             │      │                                 │        │
│   │                             ▼      ▼                                 │        │
│   │                    ┌─────────────────────┐                           │        │
│   │                    │    Shared EFS      │                           │        │
│   │                    │  (/wp-content)     │                           │        │
│   │                    │  • Plugins        │                           │        │
│   │                    │  • Themes         │                           │        │
│   │                    │  • Uploads        │                           │        │
│   │                    └─────────┬─────────┘                           │        │
│   │                              │                                       │        │
│   └──────────────────────────────┼───────────────────────────────────────┘        │
│                                  │                                                │
│                                  ▼                                                │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                          RDS MySQL                                        │   │
│   │   ┌─────────────────────────────────────────────────────────────────┐   │   │
│   │   │  Tables: wp_posts, wp_users, wp_options, wp_terms, etc.       │   │   │
│   │   └─────────────────────────────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Module Dependency Flow

### Terraform Module Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           MODULE DEPENDENCY FLOW                                    │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│                           ┌──────────────┐                                         │
│                           │    Root      │                                         │
│                           │   main.tf    │                                         │
│                           └──────┬───────┘                                         │
│                                  │                                                 │
│          ┌───────────────────────┼───────────────────────┐                         │
│          │                       │                       │                         │
│          ▼                       ▼                       ▼                         │
│   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐                   │
│   │     VPC      │      │     ECR      │      │     IAM      │                   │
│   │  (networking)│      │  (registry)  │      │   (roles)    │                   │
│   └──────┬───────┘      └──────────────┘      └──────┬───────┘                   │
│          │                                          │                             │
│          │                                          │                             │
│          ▼                                          │                             │
│   ┌──────────────┐                                  │                             │
│   │   Security   │◄─────────────────────────────────┘                             │
│   │ (SGs, rules) │                                                                  │
│   └──────┬───────┘                                                                  │
│          │                                                                           │
│    ┌─────┴─────┬─────────────────┬─────────────────┐                               │
│    ▼           ▼                 ▼                 ▼                                │
│ ┌──────┐  ┌──────┐         ┌──────┐         ┌──────┐                             │
│ │  ALB │  │  EFS │         │  RDS │         │ RDS │                             │
│ │      │  │      │         │      │         │( SG)│                             │
│ └──┬───┘  └──┬───┘         └──┬───┘         └──────┘                             │
│    │        │                │                                               │
│    │        │                │                                               │
│    │        │                │                                               │
│    │        │                │                                               │
│    ▼        ▼                ▼                                               │
│ ┌─────────────────────────────────────────────┐                                 │
│ │                  ECS Cluster                 │                                 │
│ │  ┌────────────────┐  ┌────────────────┐     │                                 │
│ │  │ ECS Primary    │  │ ECS Backup    │     │                                 │
│ │  │ (FARGATE)     │  │(FARGATE_SPOT) │     │                                 │
│ │  └───────┬────────┘  └───────┬────────┘     │                                 │
│ └──────────┼──────────────────┼───────────────┘                                 │
│            │                  │                                                 │
│            │                  │                                                 │
│            ▼                  ▼                                                 │
│     ┌─────────────────────────────────────────┐                                  │
│     │           EC2 Admin (t3.micro)          │                                  │
│     │  (WordPress Admin - admin.yourdomain)   │                                  │
│     └─────────────────────────────────────────┘                                  │
│            │                                                                  │
│            │                                                                  │
│            ▼                                                                  │
│     ┌──────────────┐                                                         │
│     │   Route53    │                                                         │
│     │    (DNS)     │                                                         │
│     └──────────────┘                                                         │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### Dependency Order

| Step | Module | Dependencies | Creates |
|------|--------|--------------|---------|
| 1 | VPC | None | VPC, Subnets, Route Tables |
| 2 | IAM | None | ECS Execution Role, Task Role |
| 3 | ECR | None | Docker Repository |
| 4 | Security | VPC | Security Groups |
| 5 | RDS | VPC, Security | MySQL Database |
| 6 | EFS | VPC, Security | File System, Access Point |
| 7 | ALB | VPC, Security | Load Balancer, Target Groups |
| 8 | ECS Primary | All above | Cluster, Task Definition, Service |
| 9 | ECS Backup | All above | Cluster, Task Definition, Service |
| 10 | EC2 Admin | VPC, Security, EFS | EC2 Instance |
| 11 | Route53 | ALB | DNS Records |

---

## Data Flow Diagrams

### Request Flow: Public Site (yourdomain.com)

```
User Browser
     │
     │ 1. DNS Query: yourdomain.com
     ▼
Route53
     │
     │ 2. Returns ALB DNS
     ▼
Application Load Balancer
     │
     │ 3. Host: yourdomain.com
     │ 4. Route to ECS Target Group
     ▼
ECS Fargate (Primary) - Nginx
     │
     │ 5. Forward to PHP-FPM
     ▼
WordPress PHP-FPM Container
     │
     │ 6. Read/Write wp-content from EFS
     │ 7. Read/Write database from RDS
     ▼
Response to User
```

### Request Flow: Admin Site (admin.yourdomain.com)

```
User Browser
     │
     │ 1. DNS Query: admin.yourdomain.com
     ▼
Route53
     │
     │ 2. Returns ALB DNS
     ▼
Application Load Balancer
     │
     │ 3. Host: admin.yourdomain.com
     │ 4. Route to EC2 Admin Target Group
     ▼
EC2 Admin Server - Nginx
     │
     │ 5. Forward to PHP-FPM
     ▼
WordPress PHP-FPM
     │
     │ 6. Read/Write wp-content from EFS (shared)
     │ 7. Read/Write database from RDS (shared)
     ▼
Response to User
```

---

## Security Groups Flow

### Traffic Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           SECURITY GROUPS FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  Internet (0.0.0.0/0)                                                              │
│         │                                                                           │
│         │ HTTP(80), HTTPS(443)                                                     │
│         ▼                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                    sg-alb-public (Public ALB)                               │   │
│  │  Inbound: HTTP(80), HTTPS(443) from 0.0.0.0/0                              │   │
│  │  Outbound: HTTP(80) to ECS and EC2 Admin (via host-based routing)        │   │
│  └──────────────────────────────────┬──────────────────────────────────────────┘   │
│                                     │                                               │
│                                     │ HTTP(80) to yourdomain.com                   │
│                                     ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │              sg-ecs (ECS Tasks) - Blue/Green Target Groups                   │   │
│  │  Inbound: HTTP(80) from ALB                                                │   │
│  │  Outbound: All to 0.0.0.0/0                                                │   │
│  └────────────────────────────┬────────────────────────────────────────────────┘   │
│                               │                                                     │
│                               │ HTTP(80) to admin.yourdomain.com                   │
│                               ▼                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                    sg-ec2-admin (EC2 Admin)                                 │   │
│  │  Inbound: HTTP(80) from ALB                                                │   │
│  │  Inbound: SSH(22) from VPC CIDR                                          │   │
│  │  Outbound: All to 0.0.0.0/0                                                │   │
│  └────────────────────────────┬────────────────────────────────────────────────┘   │
│                               │                                                     │
│                 ┌─────────────┴─────────────┐                                       │
│                 │ NFS(2049)                │ MySQL(3306)                          │
│                 ▼                          ▼                                       │
│  ┌──────────────────────────────┐    ┌────────────────────────────────────┐      │
│  │        sg-efs (EFS)        │    │        sg-database (RDS)          │      │
│  │  Inbound: NFS(2049) from  │    │  Inbound: MySQL(3306) from        │      │
│  │         sg-ecs, sg-ec2-    │    │         sg-ecs, sg-ec2-admin      │      │
│  │         admin              │    │                                   │      │
│  └────────────────────────────┘    └────────────────────────────────────┘      │
│                                                                                      │
│  Note: Single ALB with host-based routing handles both public and admin traffic   │
└─────────────────────────────────────────────────────────────────────────────────────┘
```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           SECURITY GROUPS FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  Internet (0.0.0.0/0)                                                              │
│         │                                                                           │
│         │ HTTP(80), HTTPS(443)                                                     │
│         ▼                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                    sg-alb-public (Public ALB)                               │   │
│  │  Inbound: HTTP(80), HTTPS(443) from 0.0.0.0/0                              │   │
│  │  Outbound: All traffic to VPC                                               │   │
│  └──────────────────────────────────┬──────────────────────────────────────────┘   │
│                                     │                                               │
│                                     │ HTTP(80)                                      │
│                                     ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                    sg-alb-internal (Internal ALB)                          │   │
│  │  Inbound: HTTP(80), HTTPS(443) from VPC CIDR (11.0.0.0/16)               │   │
│  │  Outbound: All traffic to VPC                                              │   │
│  └──────────────────────────────────┬──────────────────────────────────────────┘   │
│                                     │                                               │
│                    ┌───────────────┴───────────────┐                             │
│                    │                               │                             │
│                    │ HTTP(80)                      │ HTTP(80)                    │
│                    ▼                               ▼                             │
│  ┌──────────────────────────────┐    ┌────────────────────────────────────┐      │
│  │       sg-ecs (ECS Tasks)     │    │    sg-ec2-admin (EC2 Admin)        │      │
│  │  Inbound: HTTP(80) from ALB  │    │  Inbound: HTTP(80) from ALB       │      │
│  │  Outbound: All to 0.0.0.0/0  │    │  Inbound: SSH(22) from VPC       │      │
│  └──────────────┬───────────────┘    │  Outbound: All to 0.0.0.0/0     │      │
│                 │                      └──────────────┬───────────────────┘      │
│                 │ NFS(2049)                               │                        │
│                 │ MySQL(3306)                             │ NFS(2049)             │
│                 │                                          │ MySQL(3306)          │
│                 ▼                                          ▼                      │
│  ┌──────────────────────────────┐    ┌────────────────────────────────────┐      │
│  │        sg-efs (EFS)        │    │        sg-database (RDS)          │      │
│  │  Inbound: NFS(2049) from  │    │  Inbound: MySQL(3306) from        │      │
│  │         sg-ecs, sg-ec2-    │    │         sg-ecs, sg-ec2-admin      │      │
│  │         admin              │    │                                   │      │
│  └──────────────────────────────┘    └────────────────────────────────────┘      │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### Security Group Rules Summary

| From | To | Port | Protocol | Purpose |
|------|-----|------|----------|---------|
| Internet | ALB (Public) | 80, 443 | TCP | User access |
| ALB (Public) | ECS | 80 | TCP | Web traffic (yourdomain.com) |
| ALB (Public) | EC2 Admin | 80 | TCP | Admin access (admin.yourdomain.com) |
| VPC CIDR | EC2 Admin | 22 | TCP | SSH (if needed) |
| ECS | EFS | 2049 | NFS | File storage |
| EC2 Admin | EFS | 2049 | NFS | File storage |
| ECS | RDS | 3306 | TCP | Database |
| EC2 Admin | RDS | 3306 | TCP | Database |

---

## Deployment Order

### Terraform Deployment Sequence

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                          DEPLOYMENT SEQUENCE                                        │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  Phase 1: Networking                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐     │
│  │ 1.1 Initialize Terraform                                                    │     │
│  │     $ terraform init                                                       │     │
│  │                                                                            │     │
│  │ 1.2 Create VPC                                                            │     │
│  │     $ terraform apply -target module.vpc                                  │     │
│  │                                                                            │     │
│  │ 1.3 Create Security Groups                                                │     │
│  │     $ terraform apply -target module.security                             │     │
│  └────────────────────────────────────────────────────────────────────────────┘     │
│           │                                                                     │
│           ▼                                                                     │
│  Phase 2: Core Services                                                             │
│  ┌────────────────────────────────────────────────────────────────────────────┐     │
│  │ 2.1 Create IAM Roles                                                     │     │
│  │     $ terraform apply -target module.iam                                  │     │
│  │                                                                            │     │
│  │ 2.2 Create ECR Repository                                                │     │
│  │     $ terraform apply -target module.ecr                                  │     │
│  │                                                                            │     │
│  │ 2.3 Create RDS                                                            │     │
│  │     $ terraform apply -target module.rds                                  │     │
│  │                                                                            │     │
│  │ 2.4 Create EFS                                                            │     │
│  │     $ terraform apply -target module.efs                                   │     │
│  └────────────────────────────────────────────────────────────────────────────┘     │
│           │                                                                     │
│           ▼                                                                     │
│  Phase 3: Load Balancer                                                             │
│  ┌────────────────────────────────────────────────────────────────────────────┐     │
│  │ 3.1 Create ALB                                                           │     │
│  │     $ terraform apply -target module.alb                                  │     │
│  │                                                                            │     │
│  │ 3.2 Create Route53 DNS Records                                           │     │
│  │     $ terraform apply -target module.route53                             │     │
│  └────────────────────────────────────────────────────────────────────────────┘     │
│           │                                                                     │
│           ▼                                                                     │
│  Phase 4: Compute Services                                                         │
│  ┌────────────────────────────────────────────────────────────────────────────┐     │
│  │ 4.1 Create ECS Cluster & Services                                        │     │
│  │     $ terraform apply -target module.ecs_primary                          │     │
│  │     $ terraform apply -target module.ecs_backup                          │     │
│  │                                                                            │     │
│  │ 4.2 Create EC2 Admin Server                                              │     │
│  │     $ terraform apply -target module.ec2_admin                            │     │
│  └────────────────────────────────────────────────────────────────────────────┘     │
│           │                                                                     │
│           ▼                                                                     │
│  Phase 5: Finalize                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────────┐     │
│  │ 5.1 Review Outputs                                                        │     │
│  │     $ terraform output                                                    │     │
│  │                                                                            │     │
│  │ 5.2 Verify Deployment                                                    │     │
│  │     - Check ECS services are RUNNING                                     │     │
│  │     - Check EC2 instance is HEALTHY                                      │     │
│  │     - Verify DNS resolves correctly                                       │     │
│  └────────────────────────────────────────────────────────────────────────────┘     │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## CI/CD Pipeline

### GitHub Actions Workflow

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           CI/CD PIPELINE FLOW                                       │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  GitHub Repository                                                                  │
│       │                                                                             │
│       │ Push to main branch                                                         │
│       │ (changes to wordpress/ or docker/)                                          │
│       ▼                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────────┐  │
│  │                         GitHub Actions Triggered                             │  │
│  │                                                                            │  │
│  │  Job: build-and-push                                                        │  │
│  │  ├── Checkout code                                                          │  │
│  │  ├── Configure AWS credentials (OIDC)                                      │  │
│  │  ├── Login to ECR                                                           │  │
│  │  ├── Build Docker image                                                    │  │
│  │  │   ├── Base: wordpress:6.4.3-php8.2-fpm-alpine                         │  │
│  │  │   └── Context: ./docker/wordpress-fpm                                  │  │
│  │  └── Push to ECR                                                           │  │
│  │       ├── Image: {registry}/wordpress:{sha}                                │  │
│  │       └── Image: {registry}/wordpress:latest                               │  │
│  └─────────────────────────┬────────────────────────────────────────────────────┘  │
│                            │                                                        │
│             ┌──────────────┴──────────────┐                                      │
│             │                             │                                       │
│             ▼                             ▼                                       │
│  ┌─────────────────────────┐    ┌─────────────────────────┐                    │
│  │  Job: deploy-primary    │    │  Job: deploy-backup     │                    │
│  │  (FARGATE - On Demand) │    │ (FARGATE_SPOT - Backup) │                    │
│  │                         │    │                         │                    │
│  │  • Update task def      │    │  • Update task def     │                    │
│  │  • Deploy to ECS        │    │  • Deploy to ECS       │                    │
│  │  • Wait for stability  │    │  • Wait for stability  │                    │
│  └────────────┬────────────┘    └────────────┬────────────┘                    │
│               │                             │                                     │
│               └──────────────┬──────────────┘                                     │
│                              ▼                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────┐  │
│  │                         Job: verify-deployment                             │  │
│  │                                                                            │  │
│  │  • Verify Primary service running                                          │  │
│  │  • Verify Backup service running                                           │  │
│  │  • Output success message                                                   │  │
│  └────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                      │
│  Result: ✓ WordPress deployed to both ECS services                                │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### CI/CD Pipeline Details

| Stage | Description | Actions |
|-------|-------------|---------|
| Trigger | Push to `main` branch | wordpress/**, docker/** |
| Build | Build Docker image | docker/build-push-action |
| Push | Push to ECR | amazon-ecr-login |
| Deploy Primary | Deploy to ECS Primary | amazon-ecs-deploy-task-definition |
| Deploy Backup | Deploy to ECS Backup | amazon-ecs-deploy-task-definition |
| Verify | Verify deployment | aws ecs describe-services |

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_REGION` | AWS region (e.g., us-east-1) |
| `AWS_ROLE_ARN` | IAM role for GitHub Actions |
| `ECR_REPOSITORY` | ECR repository name |
| `ECS_CLUSTER` | ECS cluster name |
| `ECS_TASK_DEFINITION_PRIMARY` | Primary task definition family |
| `ECS_TASK_DEFINITION_BACKUP` | Backup task definition family |

---

## Blue-Green Deployment Architecture

### Overview

The WordPress ECS infrastructure uses AWS CodeDeploy for blue-green deployments, enabling zero-downtime updates and safe rollbacks.

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                    BLUE-GREEN DEPLOYMENT ARCHITECTURE                                      │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                         CODEDEPLOY                                                │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │  Deployment Group: wordpress-production                                  │  │   │
│  │  │  • Type: BLUE_GREEN                                                    │  │   │
│  │  │  • Traffic: Canary (10% → 100%)                                        │  │   │
│  │  │  • Auto-Rollback: Enabled                                              │  │   │
│  │  │  • Termination Wait: 1 hour                                            │  │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │   │
│  └────────────────────────────────────────────────────────────────────────────────────┘   │
│                                    │                                                     │
│                                    ▼                                                     │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│  │              APPLICATION LOAD BALANCER (ALB)                                      │   │
│  │                                                                                    │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐          │   │
│  │  │ Production      │  │ Blue TG Rules   │  │  Green TG Rules     │          │   │
│  │  │ Listener (80)  │  │ (Current v1.x)  │  │  (New v2.x)        │          │   │
│  │  └────────┬────────┘  └────────┬────────┘  └──────────┬──────────┘          │   │
│  │           │                     │                       │                       │   │
│  │           │         Traffic Shift: 10%→25%→50%→75%→100%                         │   │
│  │           │                     │                       │                       │   │
│  │           ▼                     ▼                       ▼                       │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐   │   │
│  │  │                    Target Group Pair (Blue/Green)                        │   │   │
│  │  │   ┌─────────────────────┐    ┌─────────────────────┐                 │   │   │
│  │  │   │  Blue Target Group │    │ Green Target Group │                 │   │   │
│  │  │   │  (Current Ver)   │    │  (New Version)    │                 │   │   │
│  │  │   │  WordPress v1.x  │    │  WordPress v2.x  │                 │   │   │
│  │  │   └─────────┬───────────┘    └─────────┬───────────┘                 │   │   │
│  │  └─────────────┼──────────────────────────┼─────────────────────────────┘   │   │
│  │                │                          │                                 │   │
│  │                ▼                          ▼                                 │   │
│  │  ┌────────────────────────┐    ┌────────────────────────┐              │   │
│  │  │ ECS Service (Blue)   │    │ ECS Service (Green)   │              │   │
│  │  │ • Primary (FARGATE)  │    │ • Primary (FARGATE)  │              │   │
│  │  │ • Backup (SPOT)      │    │ • Backup (SPOT)      │              │   │
│  │  └────────────────────────┘    └────────────────────────┘              │   │
│  │                                                                                    │   │
│  └────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Traffic Shift Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                           CANARY DEPLOYMENT FLOW                                         │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  Time    │  Blue (old)  │  Green (new) │  Description                                │
│  (min)   │              │              │                                             │
│  ───────────────────────────────────────────────────────────────────────────────────  │
│  0       │  100%        │  0%         │  Initial state - all traffic on blue        │
│  1       │  90%         │  10%         │  Start canary - 10% to green               │
│  2       │  80%         │  20%         │  Increase to 20%                            │
│  3       │  70%         │  30%         │  Increase to 30%                            │
│  4       │  60%         │  40%         │  Increase to 40%                            │
│  5       │  50%         │  50%         │  Halfway point                             │
│  6       │  40%         │  60%         │  Increase to 60%                            │
│  7       │  30%         │  70%         │  Increase to 70%                            │
│  8       │  20%         │  80%         │  Increase to 80%                            │
│  9       │  10%         │  90%         │  Increase to 90%                            │
│  10      │  0%          │  100%        │  Complete - all traffic on green            │
│                                                                                          │
│  After 1hr│  TERMINATED  │  100%        │  Blue terminated, green is production      │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Rollback Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                           ROLLBACK FLOW                                                │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  1. FAILURE DETECTED                                                                    │
│     ┌────────────────────────────────────────────────────────────────────────────┐       │
│     │  • Health check fails (3 consecutive failures)                          │       │
│     │  • Application error rate > 50% over 1 minute                         │       │
│     │  • Manual trigger                                                     │       │
│     └────────────────────────────────────────────────────────────────────────────┘       │
│                                    │                                                     │
│                                    ▼                                                     │
│  2. AUTO-ROLLBACK TRIGGERED                                                              │
│     ┌────────────────────────────────────────────────────────────────────────────┐       │
│     │  • Stop traffic to GREEN environment                                    │       │
│     │  • Route 100% back to BLUE                                            │       │
│     │  • Keep GREEN for 1 hour (debugging) OR terminate immediately         │       │
│     │  • Send SNS notification                                               │       │
│     └────────────────────────────────────────────────────────────────────────────┘       │
│                                    │                                                     │
│                                    ▼                                                     │
│  3. ROLLBACK COMPLETE                                                                   │
│     ┌────────────────────────────────────────────────────────────────────────────┐       │
│     │  • Traffic: 100% on BLUE (previous working version)                    │       │
│     │  • GREEN terminated or retained for 1 hour                             │       │
│     │  • Deployment marked as ROLLED_BACK                                    │       │
│     │  • Notification sent to stakeholders                                    │       │
│     └────────────────────────────────────────────────────────────────────────────┘       │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### CodeDeploy Integration with GitHub Actions

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                      CODEPLOY GITHUB ACTIONS WORKFLOW                                    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────┐        │
│  │  JOB: build                                                                   │        │
│  │  ├── Checkout code                                                            │        │
│  │  ├── Configure AWS credentials                                                │        │
│  │  ├── Login to ECR                                                           │        │
│  │  ├── Build Docker image                                                      │        │
│  │  └── Push to ECR                                                            │        │
│  └────────────────────────────────┬────────────────────────────────────────────┘        │
│                                   │                                                      │
│                                   ▼                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐        │
│  │  JOB: create-deployment                                                       │        │
│  │  ├── Get current task definition                                            │        │
│  │  ├── Create new task definition with new image                              │        │
│  │  ├── Create CodeDeploy deployment                                           │        │
│  │  └── Wait for deployment completion                                         │        │
│  └────────────────────────────────┬────────────────────────────────────────────┘        │
│                                   │                                                      │
│                                   ▼                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐        │
│  │  JOB: verify                                                                  │        │
│  │  ├── Check ECS service status                                                │        │
│  │  ├── Verify ALB target groups                                                │        │
│  │  └── Send success/failure notification                                      │        │
│  └────────────────────────────────┬────────────────────────────────────────────┘        │
│                                   │                                                      │
│                    ┌──────────────┴──────────────┐                                     │
│                    │                             │                                      │
│                    ▼                             ▼                                      │
│           ┌───────────────────┐         ┌───────────────────┐                        │
│           │   SUCCESS         │         │    FAILURE        │                        │
│           │                   │         │                   │                        │
│           │ Complete         │         │ Trigger rollback  │                        │
│           │ deployment       │         │ to BLUE          │                        │
│           └───────────────────┘         └───────────────────┘                        │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Deployment Configuration Summary

| Feature | Current Setting | Description |
|---------|----------------|-------------|
| **Deployment Type** | Blue-Green | Two environments, traffic switch |
| **Traffic Strategy** | Canary (10% → 100%) | Gradual traffic shift |
| **Step Interval** | 1 minute | Time between traffic increases |
| **Initial Traffic** | 10% | First portion to new version |
| **Auto-Rollback** | Enabled | On health check or deployment failure |
| **Termination Wait** | 1 hour | Keep old version for debugging |
| **Health Check** | /wp-content/plugins/ | Path for health verification |

---

## Auto-Scaling (Commented Out)

The current architecture has auto-scaling commented out. To enable it, uncomment the relevant resources in `terraform/modules/ecs/main.tf`.

### Auto-Scaling Configuration (When Enabled)

```hcl
# Auto-scaling target
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/wordpress-cluster/wordpress"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU-based scaling
resource "aws_appautoscaling_policy" "cpu_scaling" {
  target_value       = 70
  predefined_metric_type = "ECSServiceAverageCPUUtilization"
}

# Memory-based scaling  
resource "aws_appautoscaling_policy" "memory_scaling" {
  target_value       = 70
  predefined_metric_type = "ECSServiceAverageMemoryUtilization"
}
```

---

## Summary

This architecture provides:

- **High Availability**: Dual ECS services (Primary + Backup)
- **Cost Optimization**: FARGATE_SPOT for backup, t3.micro for admin
- **Security**: VPC isolation, security groups, encryption at rest and in transit
- **Scalability**: EFS shared storage, ALB load balancing
- **Automation**: GitHub Actions CI/CD pipeline
- **Blue-Green Deployments**: Zero-downtime updates with automatic rollback
- **Canary Releases**: Gradual traffic shifting for safe deployments

---

*Last Updated: 2026-02-26*
