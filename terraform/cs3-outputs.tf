# ============================================================================
# CS3 Outputs
# ============================================================================

# EKS Cluster Outputs
output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "eks_cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = try(aws_eks_cluster.main.identity[0].oidc[0].issuer, "")
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "eks_node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "eks_node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = aws_security_group.eks_nodes.id
}

# Kubeconfig
output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name} --profile student"
}

# # Employee Database Outputs
# output "employee_db_endpoint" {
#   description = "Employee database endpoint"
#   value       = aws_db_instance.employee.endpoint
# }

# output "employee_db_address" {
#   description = "Employee database address (hostname only)"
#   value       = aws_db_instance.employee.address
# }

# output "employee_db_name" {
#   description = "Employee database name"
#   value       = aws_db_instance.employee.db_name
# }

# output "employee_db_dns" {
#   description = "Internal DNS name for employee database"
#   value       = aws_route53_record.employee_db.fqdn
# }

# output "employee_db_secret_arn" {
#   description = "ARN of the secret containing employee database credentials"
#   value       = aws_secretsmanager_secret.employee_db_credentials.arn
# }

# output "employee_db_secret_command" {
#   description = "Command to retrieve database credentials"
#   value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.employee_db_credentials.arn} --query SecretString --output text --profile student | jq ."
# }

# Cognito Outputs
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.employees.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.employees.arn
}

output "cognito_user_pool_endpoint" {
  description = "Cognito User Pool Endpoint"
  value       = aws_cognito_user_pool.employees.endpoint
}

output "cognito_client_id" {
  description = "Cognito App Client ID"
  value       = aws_cognito_user_pool_client.employee_portal.id
}

output "cognito_domain" {
  description = "Cognito Domain"
  value       = "https://${aws_cognito_user_pool_domain.employees.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "cognito_create_user_command" {
  description = "Command to create a test user"
  value       = "aws cognito-idp admin-create-user --user-pool-id ${aws_cognito_user_pool.employees.id} --username testuser --user-attributes Name=email,Value=test@example.com Name=name,Value='Test User' --temporary-password 'TempPass123!' --profile student"
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for CS3"
  sensitive   = true
  value = {
    configure_kubectl = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name} --profile student"
    verify_nodes      = "kubectl get nodes"
    # get_db_credentials = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.employee_db_credentials.arn} --query SecretString --output text --profile student | jq ."
    connect_to_db      = "kubectl exec -it postgres-0 -- psql -U admin -d employees"
    view_eks_pods      = "kubectl get pods --all-namespaces"
    view_eks_services  = "kubectl get svc --all-namespaces"
    connect_via_vpn    = "sudo openvpn client.ovpn"
    access_grafana_vpn = "http://${aws_instance.monitoring.private_ip}:3000"
  }
}

# AWS Console Links
output "aws_console_links" {
  description = "Quick links to AWS Console"
  value = {
    eks_cluster = "https://${var.aws_region}.console.aws.amazon.com/eks/home?region=${var.aws_region}#/clusters/${aws_eks_cluster.main.name}"
    # employee_db     = "https://${var.aws_region}.console.aws.amazon.com/rds/home?region=${var.aws_region}#database:id=${aws_db_instance.employee.identifier}"
    secrets_manager = "https://${var.aws_region}.console.aws.amazon.com/secretsmanager/home?region=${var.aws_region}"
    # identity_center = "https://console.aws.amazon.com/singlesignon/home"
    cloudwatch_logs = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups"
  }
}

# Important Notes
output "important_notes" {
  description = "Important setup notes"
  value = {
    note_1 = "Authentication is handled by AWS Cognito. Ensure the User Pool is created."
    note_2 = "After deployment, configure kubectl using: aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name} --profile student"
    note_3 = "Database runs as PostgreSQL StatefulSet in Kubernetes"
    note_4 = "Connect to cluster via VPN for private access to Grafana and other internal services"
    note_5 = "Install AWS Load Balancer Controller and EBS CSI Driver add-ons using Helm after cluster creation"
  }
}

output "employee_portal_sa_role_arn" {
  description = "IAM Role ARN for employee portal service account"
  value       = aws_iam_role.employee_portal_sa.arn
}

output "aws_region" {
  description = "The AWS region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "The AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}