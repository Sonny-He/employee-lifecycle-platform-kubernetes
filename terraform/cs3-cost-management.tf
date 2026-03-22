# ----------------------------------------------------------------------------
# Cost Allocation Tags (Applied to All Resources)
# ----------------------------------------------------------------------------
locals {
  cost_allocation_tags = {
    Project     = var.project_name
    Environment = var.environment
    CostCenter  = "IT-Infrastructure"
    Owner       = "Student-Team"
    ManagedBy   = "Terraform"
    Semester    = "2024-2025-P3"
    CaseStudy   = "CS3"
  }
}

# ----------------------------------------------------------------------------
# AWS Budgets - Cost Alerts
# ----------------------------------------------------------------------------

# Monthly budget with email alerts
resource "aws_budgets_budget" "monthly_cost" {
  name              = "${var.project_name}-monthly-budget"
  budget_type       = "COST"
  limit_amount      = var.monthly_budget_limit
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())

  cost_filter {
    name = "TagKeyValue"
    values = [
      "user:Project$${var.project_name}"
    ]
  }

  # Alert at 50% of budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  # Alert at 80% of budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  # Alert at 100% of budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  # Forecasted alert at 100%
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_alert_emails
  }

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-monthly-budget"
      Environment = var.environment
    }
  )
}

# Budget for EKS specifically (highest cost component)
resource "aws_budgets_budget" "eks_cost" {
  name              = "${var.project_name}-eks-budget"
  budget_type       = "COST"
  limit_amount      = var.eks_monthly_budget_limit
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())

  cost_filter {
    name = "Service"
    values = [
      "Amazon Elastic Kubernetes Service",
      "Amazon Elastic Compute Cloud - Compute"
    ]
  }

  cost_filter {
    name = "TagKeyValue"
    values = [
      "user:Project$${var.project_name}"
    ]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-eks-budget"
      Environment = var.environment
    }
  )
}

# ----------------------------------------------------------------------------
# Cost Explorer - Saved Reports
# ----------------------------------------------------------------------------

# Note: AWS Cost Explorer API requires Cost Explorer to be enabled manually
# These are exported as outputs for manual configuration

output "cost_explorer_setup_instructions" {
  description = "Instructions for setting up Cost Explorer reports"
  value       = <<-EOT
    AWS Cost Explorer Setup:
    
    1. Enable Cost Explorer:
       - Go to AWS Console → Cost Management → Cost Explorer
       - Click "Enable Cost Explorer"
    
    2. Create custom report for this project:
       - Filter by Tag: Project = ${var.project_name}
       - Group by: Service
       - Time range: Last 3 months
       - Save as: "CS3-MA-NCA-Monthly-Report"
    
    3. Set up Cost Anomaly Detection:
       - Go to Cost Anomaly Detection
       - Create monitor for tag: Project = ${var.project_name}
       - Set email notifications to: ${join(", ", var.budget_alert_emails)}
    
    4. Review costs weekly:
       aws ce get-cost-and-usage \
         --time-period Start=2024-11-01,End=2024-11-30 \
         --granularity MONTHLY \
         --metrics "UnblendedCost" \
         --filter file://cost-filter.json \
         --profile student
  EOT
}

# ----------------------------------------------------------------------------
# Cost Optimization Recommendations (Documentation)
# ----------------------------------------------------------------------------
output "cost_optimization_recommendations" {
  description = "Cost optimization recommendations"
  value       = <<-EOT
    Cost Optimization Recommendations:
    
    Current Configuration Costs (Estimated Monthly):
    - EKS Cluster Control Plane: ~$73/month (flat rate)
    - EKS Worker Nodes (2x t3.medium): ~$60/month
    - RDS PostgreSQL (db.t3.micro): ~$15/month
    - NAT Instance (t3.micro): ~$7/month
    - Data Transfer: ~$5-10/month
    - CloudWatch Logs: ~$5/month
    - S3 Storage: ~$1-2/month
    TOTAL: ~$166-173/month
    
    Optimization Opportunities:
    1. Use Spot Instances for EKS nodes (60% savings): ~$24/month vs $60/month
    2. Stop non-production resources outside business hours (40% savings)
    3. Use S3 Lifecycle policies for old logs (50% savings on storage)
    4. Enable RDS storage autoscaling to avoid over-provisioning
    5. Use VPC endpoints instead of NAT for AWS service calls (saves data transfer)
    
    Free Tier Usage (First 12 months):
    - EC2: 750 hours/month of t2.micro/t3.micro (covers NAT and workstations)
    - RDS: 750 hours/month of db.t2.micro/db.t3.micro
    - S3: 5GB standard storage
    - CloudWatch: 10 custom metrics and 10 alarms
    
    Cost Monitoring Commands:
    # Get current month costs
    aws ce get-cost-and-usage \
      --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
      --granularity DAILY \
      --metrics UnblendedCost \
      --profile student
    
    # Get costs by service
    aws ce get-cost-and-usage \
      --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
      --granularity MONTHLY \
      --metrics UnblendedCost \
      --group-by Type=DIMENSION,Key=SERVICE \
      --profile student
  EOT
}

# ----------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------
output "monthly_budget_name" {
  description = "Name of the monthly budget"
  value       = aws_budgets_budget.monthly_cost.name
}

output "eks_budget_name" {
  description = "Name of the EKS-specific budget"
  value       = aws_budgets_budget.eks_cost.name
}

output "cost_tracking_tags" {
  description = "Tags used for cost allocation"
  value       = local.cost_allocation_tags
}