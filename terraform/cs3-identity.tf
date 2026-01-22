# ============================================================================
# CS3 Identity Management - AWS Cognito (IAM Identity Center Alternative)
# ============================================================================

# Cognito User Pool for employee authentication
resource "aws_cognito_user_pool" "employees" {
  name = "${var.project_name}-employees"

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # Auto-verify email
  auto_verified_attributes = ["email"]

  # User attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = false
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  schema {
    name                     = "department"
    attribute_data_type      = "String"
    required                 = false
    mutable                  = true
    developer_only_attribute = false
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-employee-user-pool"
      Environment = var.environment
    }
  )

  lifecycle {
    ignore_changes = [schema]
  }

}

# Cognito User Pool Client (for employee portal)
resource "aws_cognito_user_pool_client" "employee_portal" {
  name         = "${var.project_name}-employee-portal"
  user_pool_id = aws_cognito_user_pool.employees.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [name]
  }

}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "employees" {
  domain       = "${var.project_name}-employees-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.employees.id
}

# Cognito Groups for RBAC
resource "aws_cognito_user_group" "admins" {
  name         = "admins"
  user_pool_id = aws_cognito_user_pool.employees.id
  description  = "Administrator group with full access"
  precedence   = 1
}

resource "aws_cognito_user_group" "developers" {
  name         = "developers"
  user_pool_id = aws_cognito_user_pool.employees.id
  description  = "Developer group with limited access"
  precedence   = 2
}

resource "aws_cognito_user_group" "employees_group" {
  name         = "employees"
  user_pool_id = aws_cognito_user_pool.employees.id
  description  = "Standard employee access"
  precedence   = 3
}

# Auto-create Kubernetes ConfigMap with Cognito values
resource "kubernetes_config_map" "cognito_config" {
  metadata {
    name      = "cognito-config"
    namespace = "employee-services"
  }

  data = {
    user_pool_id = aws_cognito_user_pool.employees.id
    client_id    = aws_cognito_user_pool_client.employee_portal.id
    region       = var.aws_region
    domain       = aws_cognito_user_pool_domain.employees.domain
  }

  depends_on = [
    kubernetes_namespace.employee_services
  ]
}

# Create namespace if it doesn't exist
resource "kubernetes_namespace" "employee_services" {
  metadata {
    name = "employee-services"
    labels = {
      name       = "employee-services"
      managed-by = "terraform"
    }
  }
}

# Identity Pool for AWS credentials (optional, for advanced use)
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${var.project_name}-identity-pool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.employee_portal.id
    provider_name           = aws_cognito_user_pool.employees.endpoint
    server_side_token_check = true
  }

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-identity-pool"
      Environment = var.environment
    }
  )
}

# IAM role for authenticated Cognito users
resource "aws_iam_role" "cognito_authenticated" {
  name = "${var.project_name}-cognito-authenticated"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "cognito-identity.amazonaws.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "authenticated"
        }
      }
    }]
  })

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-cognito-authenticated-role"
      Environment = var.environment
    }
  )
}

# Attach policy to authenticated role
resource "aws_iam_role_policy" "cognito_authenticated" {
  name = "${var.project_name}-cognito-authenticated-policy"
  role = aws_iam_role.cognito_authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-identity:GetCredentialsForIdentity",
          "cognito-identity:GetId"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach identity pool roles
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    "authenticated" = aws_iam_role.cognito_authenticated.arn
  }
}

# Admin User for Initial Access
resource "aws_cognito_user" "admin" {
  user_pool_id = aws_cognito_user_pool.employees.id
  username     = "admin"

  attributes = {
    email          = "admin@innovatech.local"
    email_verified = "true"
  }
}

# Set permanent password for admin user
resource "null_resource" "set_admin_password" {
  depends_on = [aws_cognito_user.admin]

  provisioner "local-exec" {
    command = <<EOT
      aws cognito-idp admin-set-user-password \
        --user-pool-id ${aws_cognito_user_pool.employees.id} \
        --username admin \
        --password AdminPass123! \
        --permanent \
        --region ${var.aws_region}
    EOT
  }

  triggers = {
    user_id = aws_cognito_user.admin.id
  }
}

# NEW: Add admin user to admins group
resource "null_resource" "add_admin_to_group" {
  depends_on = [
    aws_cognito_user.admin,
    aws_cognito_user_group.admins
  ]

  provisioner "local-exec" {
    command = <<EOT
      aws cognito-idp admin-add-user-to-group \
        --user-pool-id ${aws_cognito_user_pool.employees.id} \
        --username admin \
        --group-name admins \
        --region ${var.aws_region}
    EOT
  }

  triggers = {
    user_id  = aws_cognito_user.admin.id
    group_id = aws_cognito_user_group.admins.id
  }
}