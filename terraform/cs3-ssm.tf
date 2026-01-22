# ============================================================================
# SSM - Automated Software Installation (Role-Based Provisioning)
# ============================================================================

# Developer Tools Installation
resource "aws_ssm_document" "install_dev_tools" {
  name          = "${var.project_name}-install-dev-tools"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install Developer Tools via Chocolatey"
    mainSteps = [
      {
        action = "aws:runPowerShellScript"
        name   = "installSoftware"
        inputs = {
          runCommand = [
            "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
            "$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')",
            "choco install vscode -y --no-progress",
            "choco install git -y --no-progress",
            "choco install putty -y --no-progress"
          ]
        }
      }
    ]
  })

  tags = var.cs3_tags
}

resource "aws_ssm_association" "dev_tools_installer" {
  name = aws_ssm_document.install_dev_tools.name

  targets {
    key    = "tag:Role"
    values = ["Developer"]
  }

  schedule_expression = "rate(30 minutes)"
  compliance_severity = "HIGH"
}

# Admin Tools Installation
resource "aws_ssm_document" "install_admin_tools" {
  name          = "${var.project_name}-install-admin-tools"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install Admin Tools"
    mainSteps = [
      {
        action = "aws:runPowerShellScript"
        name   = "installSoftware"
        inputs = {
          runCommand = [
            # Install Chocolatey first
            "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
            "$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')",

            # Install admin tools via Chocolatey
            "choco install awscli -y --no-progress",
            "choco install notepadplusplus -y --no-progress",
            "choco install openvpn-connect -y --no-progress",

            # Install RSAT for Active Directory (Windows Server 2022)
            "Install-WindowsFeature -Name RSAT-AD-Tools -IncludeAllSubFeature -IncludeManagementTools",
            "Install-WindowsFeature -Name RSAT-ADDS -IncludeAllSubFeature",
            "Install-WindowsFeature -Name RSAT-AD-PowerShell",
            "Install-WindowsFeature -Name RSAT-ADLDS",
            "Install-WindowsFeature -Name GPMC" # Group Policy Management Console
          ]
        }
      }
    ]
  })

  tags = var.cs3_tags
}

resource "aws_ssm_association" "admin_tools_installer" {
  name = aws_ssm_document.install_admin_tools.name

  targets {
    key    = "tag:Role"
    values = ["Admin"]
  }

  schedule_expression = "rate(30 minutes)"

  apply_only_at_cron_interval = false

  compliance_severity = "HIGH"

  max_concurrency = "1"
  max_errors      = "1"
}

# Employee Tools Installation
resource "aws_ssm_document" "install_employee_tools" {
  name          = "${var.project_name}-install-employee-tools"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install Standard Employee Tools"
    mainSteps = [
      {
        action = "aws:runPowerShellScript"
        name   = "installSoftware"
        inputs = {
          runCommand = [
            "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
            "$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')",
            "choco install googlechrome -y --no-progress",
            "choco install slack -y --no-progress",
            "choco install zoom -y --no-progress"
          ]
        }
      }
    ]
  })

  tags = var.cs3_tags
}

resource "aws_ssm_association" "employee_tools_installer" {
  name = aws_ssm_document.install_employee_tools.name

  targets {
    key    = "tag:Role"
    values = ["Employee"]
  }

  schedule_expression = "rate(30 minutes)"
  compliance_severity = "HIGH"
}