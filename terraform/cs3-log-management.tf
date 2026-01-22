# ----------------------------------------------------------------------------
# CloudWatch Log Groups for Applications
# ----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "employee_portal" {
  name              = "/aws/kubernetes/${var.eks_cluster_name}/employee-portal"
  retention_in_days = 7 # Keep logs for 1 week to save costs

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-employee-portal-logs"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_log_group" "automation_service" {
  name              = "/aws/kubernetes/${var.eks_cluster_name}/automation-service"
  retention_in_days = 7

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-automation-service-logs"
      Environment = var.environment
    }
  )
}


# ----------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for monitoring"
  value = {
    employee_portal    = aws_cloudwatch_log_group.employee_portal.name
    automation_service = aws_cloudwatch_log_group.automation_service.name
    eks_cluster        = aws_cloudwatch_log_group.eks_cluster.name
  }
}