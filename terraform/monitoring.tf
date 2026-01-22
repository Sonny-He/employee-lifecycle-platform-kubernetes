# ============================================================================
# CloudWatch Monitoring - CS3 with Container Insights
# ============================================================================

# EKS Cluster CPU Alarm
resource "aws_cloudwatch_metric_alarm" "eks_cluster_high_cpu" {
  alarm_name          = "${var.project_name}-eks-cluster-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "cluster_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EKS cluster CPU utilization is high"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  tags = var.cs3_tags
}

# EKS Node Memory Alarm
resource "aws_cloudwatch_metric_alarm" "eks_node_high_memory" {
  alarm_name          = "${var.project_name}-eks-node-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EKS node memory utilization is high"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  tags = var.cs3_tags
}

# PostgreSQL Pod CPU Alarm (using Container Insights)
resource "aws_cloudwatch_metric_alarm" "postgres_high_cpu" {
  alarm_name          = "${var.project_name}-postgres-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "pod_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "PostgreSQL pod CPU utilization is high"

  dimensions = {
    ClusterName = var.eks_cluster_name
    Namespace   = "default"
    PodName     = "postgres-0"
  }

  tags = var.cs3_tags
}

# Employee Portal Pod CPU Alarm
resource "aws_cloudwatch_metric_alarm" "portal_high_cpu" {
  alarm_name          = "${var.project_name}-portal-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "pod_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Employee portal pod CPU utilization is high"

  dimensions = {
    ClusterName = var.eks_cluster_name
    Namespace   = "employee-services"
  }

  tags = var.cs3_tags
}