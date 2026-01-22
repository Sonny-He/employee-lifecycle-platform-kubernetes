# # ============================================================================
# # CS3 Employee Database (RDS PostgreSQL)
# # ============================================================================

# # Random password for database
# resource "random_password" "employee_db" {
#   length  = 16
#   special = true
# }

# # Store credentials in Secrets Manager
# resource "aws_secretsmanager_secret" "employee_db_credentials" {
#   name_prefix = "${var.project_name}-employee-db-"
#   description = "Employee database credentials"

#   tags = merge(
#     var.cs3_tags,
#     {
#       Name        = "${var.project_name}-employee-db-credentials"
#       Environment = var.environment
#     }
#   )
# }

# resource "aws_secretsmanager_secret_version" "employee_db_credentials" {
#   secret_id = aws_secretsmanager_secret.employee_db_credentials.id
#   secret_string = jsonencode({
#     username = var.employee_db_username
#     password = var.employee_db_password != "" ? var.employee_db_password : random_password.employee_db.result
#     engine   = "postgres"
#     host     = aws_db_instance.employee.endpoint
#     port     = 5432
#     dbname   = var.employee_db_name
#   })
# }

# # RDS Parameter Group for PostgreSQL
# resource "aws_db_parameter_group" "employee" {
#   name_prefix = "${var.project_name}-employee-pg-"
#   family      = "postgres15"
#   description = "Parameter group for employee database"

#   parameter {
#     name  = "log_connections"
#     value = "1"
#   }

#   parameter {
#     name  = "log_disconnections"
#     value = "1"
#   }

#   parameter {
#     name  = "log_duration"
#     value = "1"
#   }

#   tags = merge(
#     var.cs3_tags,
#     {
#       Name        = "${var.project_name}-employee-pg"
#       Environment = var.environment
#     }
#   )

#   lifecycle {
#     create_before_destroy = true
#   }
# }

# # RDS Instance for Employee Data
# resource "aws_db_instance" "employee" {
#   identifier     = "${var.project_name}-employee-db"
#   engine         = "postgres"
#   engine_version = var.employee_db_engine_version
#   instance_class = var.employee_db_instance_class

#   allocated_storage     = var.employee_db_allocated_storage
#   max_allocated_storage = var.employee_db_allocated_storage * 2
#   storage_type          = "gp3"
#   storage_encrypted     = true

#   db_name  = var.employee_db_name
#   username = var.employee_db_username
#   password = var.employee_db_password != "" ? var.employee_db_password : random_password.employee_db.result

#   db_subnet_group_name   = aws_db_subnet_group.employee.name
#   vpc_security_group_ids = [aws_security_group.employee_db.id]
#   parameter_group_name   = aws_db_parameter_group.employee.name

#   multi_az                  = false # Set to true for production
#   publicly_accessible       = false
#   deletion_protection       = false # Set to true for production
#   skip_final_snapshot       = true  # Set to false for production
#   final_snapshot_identifier = "${var.project_name}-employee-db-final-snapshot"

#   backup_retention_period = 7
#   backup_window           = "03:00-04:00"
#   maintenance_window      = "mon:04:00-mon:05:00"

#   enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

#   performance_insights_enabled          = var.enable_performance_insights
#   performance_insights_retention_period = var.performance_insights_retention_period

#   copy_tags_to_snapshot = true

#   tags = merge(
#     var.cs3_tags,
#     {
#       Name        = "${var.project_name}-employee-db"
#       Environment = var.environment
#       Purpose     = "Employee-Data"
#     }
#   )
# }

# # CloudWatch Log Groups for RDS
# resource "aws_cloudwatch_log_group" "employee_db_postgresql" {
#   name              = "/aws/rds/instance/${aws_db_instance.employee.identifier}/postgresql"
#   retention_in_days = var.cloudwatch_logs_retention

#   tags = merge(
#     var.cs3_tags,
#     {
#       Name        = "${var.project_name}-employee-db-postgresql-logs"
#       Environment = var.environment
#     }
#   )
# }

# resource "aws_cloudwatch_log_group" "employee_db_upgrade" {
#   name              = "/aws/rds/instance/${aws_db_instance.employee.identifier}/upgrade"
#   retention_in_days = var.cloudwatch_logs_retention

#   tags = merge(
#     var.cs3_tags,
#     {
#       Name        = "${var.project_name}-employee-db-upgrade-logs"
#       Environment = var.environment
#     }
#   )
# }

# # Route 53 DNS record for employee database
# resource "aws_route53_record" "employee_db" {
#   zone_id = aws_route53_zone.private.zone_id
#   name    = "employee-db.${var.route53_private_zone}"
#   type    = "CNAME"
#   ttl     = 300
#   records = [aws_db_instance.employee.address]
# }