# ============================================================================
# CS3-Specific Variables
# ============================================================================

# EKS Configuration
variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "cs3-employee-platform"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.32"
}

variable "eks_node_instance_types" {
  description = "Instance types for EKS node group"
  type        = list(string)
  default     = ["t3.small"]
}

variable "eks_node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 4
}

variable "eks_node_disk_size" {
  description = "Disk size for EKS nodes (GB)"
  type        = number
  default     = 20
}

# Employee Database Configuration
variable "employee_db_name" {
  description = "Name of the employee database"
  type        = string
  default     = "employeedb"
}

variable "employee_db_username" {
  description = "Username for employee database"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "employee_db_password" {
  description = "Password for employee database"
  type        = string
  sensitive   = true
  default     = "" # Should be set via environment variable or tfvars
}

variable "employee_db_instance_class" {
  description = "RDS instance class for employee database"
  type        = string
  default     = "db.t3.micro"
}

variable "employee_db_allocated_storage" {
  description = "Allocated storage for employee database (GB)"
  type        = number
  default     = 20
}

variable "employee_db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

# # IAM Identity Center Configuration
# variable "identity_center_instance_arn" {
#   description = "ARN of the IAM Identity Center instance (if exists)"
#   type        = string
#   default     = ""
# }

# variable "identity_store_id" {
#   description = "ID of the Identity Store (if exists)"
#   type        = string
#   default     = ""
# }

# Application Configuration
variable "portal_app_name" {
  description = "Name of the self-service portal application"
  type        = string
  default     = "employee-portal"
}

variable "portal_namespace" {
  description = "Kubernetes namespace for the portal"
  type        = string
  default     = "employee-services"
}

# Automation Configuration
variable "enable_employee_automation" {
  description = "Enable automated employee provisioning/deprovisioning"
  type        = bool
  default     = true
}

variable "automation_schedule" {
  description = "Cron schedule for automation jobs"
  type        = string
  default     = "0 */6 * * *" # Every 6 hours
}

# Security Configuration
variable "enable_pod_security_policy" {
  description = "Enable Pod Security Policy for EKS"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable Network Policy for micro-segmentation"
  type        = bool
  default     = true
}

# Cost Management
variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler for cost optimization"
  type        = bool
  default     = true
}

# Tags
variable "cs3_tags" {
  description = "Additional tags specific to CS3"
  type        = map(string)
  default = {
    CaseStudy    = "CS3"
    Project      = "Employee-Lifecycle-Platform"
    Architecture = "Kubernetes-EKS"
  }
}

# Route 53 (inherited from CS1)
variable "route53_private_zone" {
  description = "Private hosted zone name for internal DNS"
  type        = string
  default     = "cs1.local"
}

# Cost Management
variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for all resources"
  type        = number
  default     = 200
}

variable "eks_monthly_budget_limit" {
  description = "Monthly budget limit in USD for EKS specifically"
  type        = number
  default     = 150
}

variable "budget_alert_emails" {
  description = "Email addresses to receive budget alerts"
  type        = list(string)
  default     = ["548750@student.fontys.nl"]
}

variable "create_demo_workstation" {
  description = "Create demo workstation for SSM testing"
  type        = bool
  default     = false # Set to true only if you want to test SSM
}

# Active Directory Configuration
variable "ad_admin_password" {
  description = "Active Directory administrator password"
  type        = string
  sensitive   = true
  default     = "TempPassword123!@#" # Change in production!
}

variable "workspace_bundle_id" {
  description = "WorkSpaces bundle ID"
  type        = string
  default     = "wsb-93xk71ss4" # Free tier Standard bundle
}
