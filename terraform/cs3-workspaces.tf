# ============================================================================
# AWS Managed Microsoft AD & WorkSpaces
# ============================================================================

resource "aws_iam_role" "workspaces_default" {
  name = "workspaces_DefaultRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "workspaces.amazonaws.com"
      }
    }]
  })

  tags = merge(
    var.cs3_tags,
    {
      Name        = "workspaces_DefaultRole"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "workspaces_default_service_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonWorkSpacesServiceAccess"
  role       = aws_iam_role.workspaces_default.name
}

resource "aws_iam_role_policy_attachment" "workspaces_default_self_service_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonWorkSpacesSelfServiceAccess"
  role       = aws_iam_role.workspaces_default.name
}

# 1. AWS Managed Microsoft AD
resource "aws_directory_service_directory" "innovatech_ad" {
  name     = "innovatech.local"
  password = var.ad_admin_password # Using variable for security
  edition  = "Standard"
  type     = "MicrosoftAD"

  vpc_settings {
    vpc_id = aws_vpc.main.id
    # AD requires two subnets in different AZs
    subnet_ids = [aws_subnet.eks_private[0].id, aws_subnet.eks_private[1].id]
  }

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-directory"
      Environment = var.environment
    }
  )
}

# 2. Register Directory for WorkSpaces
resource "aws_workspaces_directory" "main" {
  directory_id = aws_directory_service_directory.innovatech_ad.id

  self_service_permissions {
    change_compute_type  = false
    increase_volume_size = false
    rebuild_workspace    = false
    restart_workspace    = true
    switch_running_mode  = false
  }

  subnet_ids = [aws_subnet.eks_private[0].id, aws_subnet.eks_private[1].id]

  depends_on = [
    aws_iam_role_policy_attachment.workspaces_default_service_access,
    aws_iam_role_policy_attachment.workspaces_default_self_service_access
  ]

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-workspaces-directory"
      Environment = var.environment
    }
  )
}

# 3. Security Group Rules - Allow EKS to reach AD
resource "aws_security_group_rule" "eks_to_ad_ldap" {
  type                     = "ingress"
  from_port                = 389
  to_port                  = 389
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_directory_service_directory.innovatech_ad.security_group_id
  description              = "Allow EKS pods to reach AD via LDAP"
}

resource "aws_security_group_rule" "eks_to_ad_ldaps" {
  type                     = "ingress"
  from_port                = 636
  to_port                  = 636
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_directory_service_directory.innovatech_ad.security_group_id
  description              = "Allow EKS pods to reach AD via LDAPS"
}

resource "aws_security_group_rule" "eks_to_ad_kerberos" {
  type                     = "ingress"
  from_port                = 88
  to_port                  = 88
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_directory_service_directory.innovatech_ad.security_group_id
  description              = "Allow EKS pods to reach AD via Kerberos"
}

resource "aws_security_group_rule" "eks_to_ad_dns" {
  type                     = "ingress"
  from_port                = 53
  to_port                  = 53
  protocol                 = "udp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_directory_service_directory.innovatech_ad.security_group_id
  description              = "Allow EKS pods to reach AD DNS"
}

# 4. Store AD credentials in Secrets Manager
resource "aws_secretsmanager_secret" "ad_admin" {
  name_prefix = "cs3-ad-service-account"
  description = "Active Directory admin credentials"

  tags = merge(
    var.cs3_tags,
    {
      Name        = "cs3-ad-service-account"
      Environment = var.environment
    }
  )
}

resource "aws_secretsmanager_secret_version" "ad_admin" {
  secret_id = aws_secretsmanager_secret.ad_admin.id
  secret_string = jsonencode({
    username = "Admin"
    password = var.ad_admin_password
    domain   = "innovatech.local"
  })
}

# Auto-create Kubernetes ConfigMap with AD values
resource "kubernetes_config_map" "ad_config" {
  metadata {
    name      = "ad-config"
    namespace = "employee-services"
  }

  data = {
    # Dynamically pull the ID from the resource above
    directory_id = aws_directory_service_directory.innovatech_ad.id

    # Pull ALL DNS IPs as a comma-separated string (e.g., "10.0.40.11,10.0.41.73")
    dns_ip = join(",", aws_directory_service_directory.innovatech_ad.dns_ip_addresses)

    # These are static, but good to have here for consistency
    domain    = "innovatech.local"
    bundle_id = var.workspace_bundle_id # Still hardcoded unless you automate bundle creation
  }

  depends_on = [
    aws_workspaces_directory.main
  ]
}

# ----------------------------------------------------------------------------
# SSM Permissions for WorkSpaces
# ----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "workspaces_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.workspaces_default.name
}

# 5. Outputs
output "directory_id" {
  description = "Active Directory ID"
  value       = aws_directory_service_directory.innovatech_ad.id
}

output "directory_dns_ips" {
  description = "DNS IP addresses for the directory"
  value       = aws_directory_service_directory.innovatech_ad.dns_ip_addresses
}

output "ad_setup_instructions" {
  description = "Instructions for completing WorkSpaces setup"
  value       = <<-EOT
    1. Get a WorkSpaces Bundle ID:
       aws workspaces describe-workspace-bundles --region eu-central-1 --query 'Bundles[?contains(Name, `Standard`)].{ID:BundleId,Name:Name}' --output table
    
    2. Update kubernetes/employee-portal.yaml with:
       - AD_DIRECTORY_ID: ${aws_directory_service_directory.innovatech_ad.id}
       - AD_BUNDLE_ID: <from step 1>
    
    3. AD Admin Password is stored in: ${aws_secretsmanager_secret.ad_admin.name}
  EOT
}

# ============================================================================
# ADMIN WORKSPACE - Free Tier Eligible (AlwaysOn for 12 months free)
# ============================================================================

resource "aws_workspaces_workspace" "admin" {
  directory_id = aws_directory_service_directory.innovatech_ad.id
  bundle_id    = "wsb-93xk71ss4" # Standard bundle - FREE for 12 months
  user_name    = "Admin"

  # AlwaysOn = Always ready, no startup delay, $0 for 12 months
  workspace_properties {
    running_mode         = "ALWAYS_ON"
    compute_type_name    = "STANDARD" # 2 vCPU, 4GB RAM
    user_volume_size_gib = 50         # From bundle specs
    root_volume_size_gib = 80         # From bundle specs
  }

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-admin-workspace"
      Role        = "Admin"
      CreatedBy   = "Terraform"
      Environment = "Production"
      FreeTier    = "true"
      BillingType = "AlwaysOn"
    }
  )

  depends_on = [
    aws_workspaces_directory.main
  ]
}

# ============================================================================
resource "aws_security_group_rule" "eks_to_ad_gc_ssl" {
  type                     = "ingress"
  from_port                = 3269
  to_port                  = 3269
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_directory_service_directory.innovatech_ad.security_group_id
  description              = "Allow EKS pods to reach AD Global Catalog SSL"
}

# Allow EKS Cluster Security Group (for pods)
resource "aws_security_group_rule" "eks_cluster_to_ad_ldap" {
  type                     = "ingress"
  from_port                = 389
  to_port                  = 389
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_directory_service_directory.innovatech_ad.security_group_id
  description              = "Allow EKS cluster SG to reach AD via LDAP"
}

resource "aws_security_group_rule" "eks_cluster_to_ad_ldaps" {
  type                     = "ingress"
  from_port                = 636
  to_port                  = 636
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_directory_service_directory.innovatech_ad.security_group_id
  description              = "Allow EKS cluster SG to reach AD via LDAPS"
}

# Kerberos
resource "aws_security_group_rule" "eks_cluster_to_ad_kerberos" {
  type                     = "ingress"
  from_port                = 88
  to_port                  = 88
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_directory_service_directory.innovatech_ad.security_group_id
  description              = "Allow EKS cluster SG to reach AD via Kerberos"
}

# DNS
resource "aws_security_group_rule" "eks_cluster_to_ad_dns" {
  type                     = "ingress"
  from_port                = 53
  to_port                  = 53
  protocol                 = "udp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_directory_service_directory.innovatech_ad.security_group_id
  description              = "Allow EKS cluster SG to reach AD DNS"
}

# Global Catalog SSL (port 3269)
resource "aws_security_group_rule" "eks_cluster_to_ad_gc_ssl" {
  type                     = "ingress"
  from_port                = 3269
  to_port                  = 3269
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_directory_service_directory.innovatech_ad.security_group_id
  description              = "Allow EKS cluster SG to reach AD via Global Catalog SSL"
}

# ============================================================================
# NEW RULE: Allow SMB (File Sharing) for GPO Software Installation
# ============================================================================
resource "aws_security_group_rule" "ad_allow_smb_sharing" {
  type      = "ingress"
  from_port = 445
  to_port   = 445
  protocol  = "tcp"

  # Best Practice: Allow only from inside the VPC (10.0.0.0/16)
  cidr_blocks = ["10.0.0.0/16"]

  security_group_id = aws_directory_service_directory.innovatech_ad.security_group_id
  description       = "Allow SMB File Sharing for GPO Software Deployment"
}

# ============================================================================
# WORKSPACES SECURITY GROUP RULES
# ============================================================================

# Allow SMB (Port 445) so WorkSpaces can access file shares on other WorkSpaces
# Required for: test.19 accessing \\WSAMZN-S3T3F17F\SoftwareDepot
resource "aws_security_group_rule" "workspaces_internal_smb" {
  type        = "ingress"
  from_port   = 445
  to_port     = 445
  protocol    = "tcp"
  cidr_blocks = ["10.0.0.0/16"] # Allow from entire VPC (all subnets)

  # Dynamically target the SG created by the WorkSpaces Directory registration
  security_group_id = aws_workspaces_directory.main.workspace_security_group_id

  description = "Allow SMB File Sharing between WorkSpaces"
}

# Install RSAT & Apply Tags immediately after WorkSpace is created
resource "null_resource" "install_rsat_on_admin" {
  depends_on = [
    aws_workspaces_workspace.admin,
    aws_ssm_document.install_admin_tools
  ]

  triggers = {
    workspace_id = aws_workspaces_workspace.admin.id
    ssm_document = aws_ssm_document.install_admin_tools.name
  }

  provisioner "local-exec" {
    command     = <<-EOT
      #!/bin/bash
      set -e
      
      WS_ID="${aws_workspaces_workspace.admin.id}"
      REGION="${var.aws_region}"
      
      echo "⏳ Waiting for WorkSpace $WS_ID to be AVAILABLE..."
      
      # 1. Wait for WorkSpace to be AVAILABLE
      max_retries=60
      retry_count=0
      
      while [ $retry_count -lt $max_retries ]; do
        status=$(aws workspaces describe-workspaces \
          --workspace-ids $WS_ID \
          --region $REGION \
          --query 'Workspaces[0].State' \
          --output text 2>/dev/null || echo "ERROR")
        
        if [ "$status" = "AVAILABLE" ]; then
          echo "✅ WorkSpace is AVAILABLE!"
          break
        fi
        
        echo "   Status: $status (waiting 30s...)"
        sleep 30
        retry_count=$((retry_count + 1))
      done
      
      # 2. Get the Computer Name (The link between WorkSpace and SSM)
      COMPUTER_NAME=$(aws workspaces describe-workspaces \
        --workspace-ids $WS_ID \
        --region $REGION \
        --query 'Workspaces[0].ComputerName' \
        --output text)
        
      echo "💻 Target Computer Name: $COMPUTER_NAME"
      
      # 3. Wait for SSM to recognize the computer
      echo "⏳ Waiting for SSM agent to check in..."
      INSTANCE_ID=""
      retry_count=0
      
      while [ $retry_count -lt 20 ]; do
        # Search SSM for an instance with this Computer Name
        INSTANCE_ID=$(aws ssm describe-instance-information \
          --filters "Key=ComputerName,Values=$COMPUTER_NAME" \
          --region $REGION \
          --query 'InstanceInformationList[0].InstanceId' \
          --output text 2>/dev/null || echo "None")
          
        if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
          echo "✅ Found SSM Instance ID: $INSTANCE_ID"
          break
        fi
        
        echo "   SSM not ready yet... (waiting 15s)"
        sleep 15
        retry_count=$((retry_count + 1))
      done
      
      if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
        echo "❌ Timeout: SSM agent never checked in. Check Internet/NAT gateway."
        exit 1
      fi
      
      # 4. CRITICAL FIX: Apply the 'Role' tag to the SSM Instance
      echo "Hg Applying 'Role=Admin' tag to SSM Instance..."
      aws ssm add-tags-to-resource \
        --resource-type "ManagedInstance" \
        --resource-id "$INSTANCE_ID" \
        --tags "Key=Role,Value=Admin" \
        --region $REGION
        
      echo "✅ Tag applied! SSM Association will now pick it up automatically."
      
      # 5. Force the install immediately (Optional, but faster)
      echo "🚀 Triggering Admin Tools installation..."
      aws ssm start-associations-once \
        --association-ids "${aws_ssm_association.admin_tools_installer.association_id}" \
        --region $REGION
        
    EOT
    interpreter = ["bash", "-c"]
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "admin_workspace_id" {
  description = "Admin WorkSpace ID"
  value       = aws_workspaces_workspace.admin.id
}

output "admin_workspace_state" {
  description = "Admin WorkSpace provisioning state"
  value       = aws_workspaces_workspace.admin.state
}

output "admin_workspace_ip" {
  description = "Admin WorkSpace IP address"
  value       = aws_workspaces_workspace.admin.ip_address
}

output "admin_workspace_computer_name" {
  description = "Admin WorkSpace computer name"
  value       = aws_workspaces_workspace.admin.computer_name
}

output "workspace_registration_code" {
  description = "WorkSpaces registration code for client app"
  value       = aws_workspaces_directory.main.registration_code
  sensitive   = false
}