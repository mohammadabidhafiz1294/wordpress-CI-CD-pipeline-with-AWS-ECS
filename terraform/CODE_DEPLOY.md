# CodeDeploy Blue-Green Deployment Documentation

This document provides detailed information about the CodeDeploy blue-green deployment configuration for WordPress ECS.

## Table of Contents

1. [Overview](#overview)
2. [CodeDeploy Module](#codedeploy-module)
3. [Deployment Configuration](#deployment-configuration)
4. [Traffic Shift Strategy](#traffic-shift-strategy)
5. [Rollback Configuration](#rollback-configuration)
6. [GitHub Actions Integration](#github-actions-integration)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The WordPress ECS infrastructure uses AWS CodeDeploy for blue-green deployments, enabling:

- **Zero-downtime deployments**: New version deployed without service interruption
- **Safe rollbacks**: Automatic rollback on failure
- **Traffic shifting**: Gradual traffic migration from blue to green
- **Health verification**: Automated health checks before full traffic switch

### Blue-Green Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BLUE-GREEN DEPLOYMENT ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────┐    │
│   │                        APPLICATION LOAD BALANCER                    │    │
│   │                                                                       │    │
│   │   Production Listener ──────────────────────────────────────────►  │    │
│   │   (Port 80)                                                         │    │
│   │                                                                       │    │
│   └────────────────────────────┬─────────────────────────────────────┘    │
│                                │                                             │
│                    ┌───────────┴───────────┐                                 │
│                    │                       │                                  │
│                    ▼                       ▼                                  │
│        ┌───────────────────┐    ┌───────────────────┐                    │
│        │  BLUE TARGET GROUP │    │ GREEN TARGET GROUP│                    │
│        │  (Current Version)  │    │  (New Version)   │                    │
│        │   WordPress v1.x   │    │  WordPress v2.x  │                    │
│        └─────────┬───────────┘    └────────┬──────────┘                    │
│                  │                          │                               │
│                  ▼                          ▼                               │
│        ┌───────────────────┐    ┌───────────────────┐                    │
│        │  ECS Service     │    │  ECS Service     │                    │
│        │  (Blue)         │    │  (Green)         │                    │
│        └───────────────────┘    └───────────────────┘                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## CodeDeploy Module

### Module Location
`terraform/modules/codedeploy/`

### Files

| File | Purpose |
|------|---------|
| `main.tf` | CodeDeploy application and deployment group |
| `variables.tf` | Configuration variables |
| `outputs.tf` | Output values |

### Resources Created

1. **CodeDeploy Application**
   - Name: `wordpress-ecs`
   - Compute Platform: ECS

2. **Deployment Group**
   - Name: `wordpress-production`
   - Type: Blue-Green
   - Traffic Control: Canary (10% → 100%)

3. **IAM Role**
   - Service role for CodeDeploy operations

4. **SNS Topic**
   - For deployment notifications

---

## Deployment Configuration

### Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `application_name` | string | `wordpress-ecs` | CodeDeploy application name |
| `deployment_group_name` | string | `wordpress-production` | Deployment group name |
| `deployment_config_name` | string | `CodeDeployDefault.ECSLinear10PercentEvery1Minutes` | Deployment configuration |
| `ecs_cluster_name` | string | - | ECS cluster name |
| `ecs_service_name` | string | - | ECS service name |
| `alb_listener_arn` | string | - | ALB listener ARN |
| `blue_target_group_name` | string | `wordpress-blue-tg` | Blue target group name |
| `green_target_group_name` | string | `wordpress-green-tg` | Green target group name |
| `canary_percentage` | number | `10` | Initial traffic percentage for canary |
| `step_interval_in_minutes` | number | `1` | Interval between traffic shifts |
| `wait_time_in_minutes` | number | `5` | Wait time before traffic routing completes |
| `termination_wait_time_in_minutes` | number | `60` | Time to keep blue after successful deployment |

### Deployment Configuration Options

| Configuration | Value | Description |
|---------------|-------|-------------|
| Traffic Shift Type | Canary | Gradual traffic shift |
| Initial Traffic | 10% | First 10% to new version |
| Increment | 10% per minute | Gradually increase |
| Final Traffic | 100% | Full cutover |
| Blue Termination | After 1 hour | Keep old version for 1 hour |

---

## Traffic Shift Strategy

### Canary Deployment Flow

```
Time (minutes)    Blue (old)    Green (new)    Description
─────────────────────────────────────────────────────────────────
0                 100%          0%             Initial state
1                 90%           10%            Start canary
2                 80%           20%            Increase traffic
3                 70%           30%            Continue rollout
4                 60%           40%            Continue rollout
5                 50%           50%            Halfway point
6                 40%           60%            Continue rollout
7                 30%           70%            Continue rollout
8                 20%           80%            Continue rollout
9                 10%           90%            Almost done
10                0%            100%            Complete rollout
```

### Traffic Shift Configuration

```hcl
# In codedeploy module
canary_percentage          = 10        # Start with 10%
step_interval_in_minutes   = 1         # Shift every 1 minute
termination_wait_time_in_minutes = 60  # Keep blue for 1 hour
```

---

## Rollback Configuration

### Auto-Rollback Triggers

| Event | Action |
|-------|--------|
| Deployment Failure | Automatic rollback |
| Health Check Failure | Automatic rollback |
| Stop on Warning | Automatic rollback |

### Rollback Process

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ROLLBACK FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. FAILURE DETECTED                                                        │
│     - Health check fails OR                                                 │
│     - Application error threshold exceeded                                   │
│                                                                              │
│  2. AUTO-ROLLBACK TRIGGERED                                                 │
│     - Stop traffic to GREEN                                                  │
│     - Route 100% to BLUE                                                    │
│     - Terminate GREEN tasks (if immediate) OR keep for debugging            │
│                                                                              │
│  3. ROLLBACK COMPLETE                                                        │
│     - Traffic: 100% on BLUE                                                  │
│     - GREEN terminated or retained                                          │
│     - Notification sent                                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Manual Rollback

To manually rollback:

```bash
# Get last successful deployment
aws deploy list-deployments \
  --application-name wordpress-ecs \
  --deployment-group-name wordpress-production \
  --status-contains Succeeded

# Create rollback deployment
aws deploy create-deployment \
  --application-name wordpress-ecs \
  --deployment-group-name wordpress-production \
  --revision '{"revisionType": "DeploymentId", "deploymentId": "<previous-deployment-id>"}'
```

---

## GitHub Actions Integration

### Workflow: `.github/workflows/wordpress-ci-cd.yml`

### Jobs

| Job | Description |
|-----|-------------|
| `build` | Build and push Docker image to ECR |
| `create-deployment` | Create CodeDeploy deployment |
| `verify` | Verify deployment and check health |
| `rollback` | Manual rollback on failure |
| `notify` | Send deployment notifications |

### GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `AWS_REGION` | AWS region |
| `AWS_ROLE_ARN` | IAM role for GitHub Actions |
| `AWS_ACCOUNT_ID` | AWS account ID |
| `ECR_REPOSITORY` | ECR repository name |
| `ECS_CLUSTER` | ECS cluster name |
| `ECS_SERVICE` | ECS service name |
| `DOMAIN_NAME` | WordPress domain |

### Deployment Flow

```
1. Push to main branch
       │
       ▼
2. Build Docker image
       │
       ▼
3. Push to ECR
       │
       ▼
4. Create CodeDeploy deployment
       │
       ▼
5. Deploy to GREEN (0% traffic)
       │
       ▼
6. Traffic shift: 10% → 100%
       │
       ▼
7. Verify health checks
       │
       ├── Success: Complete deployment
       │
       └── Failure: Auto-rollback to BLUE
```

---

## Troubleshooting

### Common Issues

#### 1. Deployment Fails to Start

**Symptoms**: CodeDeploy deployment stuck in "Pending" state

**Solutions**:
- Check ECS service exists and is stable
- Verify task definition is valid
- Check IAM permissions for CodeDeploy

#### 2. Health Check Failures

**Symptoms**: Deployment fails during traffic shift

**Solutions**:
- Verify health check path `/wp-content/plugins/` returns 200
- Check container logs in CloudWatch
- Ensure ALB can reach ECS tasks

#### 3. Rollback Not Triggering

**Symptoms**: Deployment fails but no automatic rollback

**Solutions**:
- Check auto-rollback configuration is enabled
- Verify health check settings
- Check CloudWatch alarms (if configured)

#### 4. Traffic Not Shifting

**Symptoms**: Traffic stays on old version

**Solutions**:
- Check listener rules are correct
- Verify target groups are registered
- Check CodeDeploy deployment configuration

### Useful Commands

```bash
# List deployments
aws deploy list-deployments \
  --application-name wordpress-ecs \
  --deployment-group-name wordpress-production

# Get deployment status
aws deploy get-deployment \
  --deployment-id <deployment-id>

# View deployment instances
aws deploy get-deployment-instance \
  --deployment-id <deployment-id> \
  --instance-id <instance-id>

# Check ECS service events
aws ecs describe-services \
  --services wordpress \
  --cluster wordpress-cluster
```

### Monitoring

- **CloudWatch Logs**: `/ecs/wordpress` log group
- **CodeDeploy Console**: Deployment history
- **ECS Console**: Service events and task status
- **ALB Console**: Target group health

---

## Security Considerations

### IAM Permissions

The CodeDeploy role requires:
- `ecs:UpdateService`
- `ecs:DescribeServices`
- `elasticloadbalancing:Describe*`
- `elasticloadbalancing:RegisterTargets`

### Network Security

- ALB in public subnets
- ECS tasks in private subnets
- Security groups restrict traffic between components
- EFS mounted with encryption

### Data Security

- EFS encryption at rest
- RDS encryption at rest
- Container images in private ECR
- No sensitive data in task definitions

---

## Maintenance

### Updating Deployment Configuration

To change traffic shift strategy:

1. Update `terraform/modules/codedeploy/variables.tf`
2. Run `terraform apply`

Example - Change to AllAtOnce:

```hcl
# In terraform.tfvars
deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
```

### Monitoring Deployments

1. **CodeDeploy Console**: View deployment history
2. **CloudWatch**: Monitor ECS metrics
3. **SNS Notifications**: Subscribe to deployment events

---

## References

- [AWS CodeDeploy Documentation](https://docs.aws.amazon.com/codedeploy/)
- [CodeDeploy ECS Deployments](https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-steps-ecs.html)
- [Blue-Green Deployments](https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-types.html#deployment-types-blue-green)

---

*Last Updated: 2026-02-26*
