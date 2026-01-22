# CS3 - Employee Lifecycle Platform

Infrastructure as Code for Case Study 3: Kubernetes-based employee lifecycle management platform with automated provisioning and self-service portal.

## Architecture Overview

- **EKS Cluster**: Managed Kubernetes for application workloads
- **Employee Database**: RDS PostgreSQL for employee data persistence
- **AWS Cognito**: User authentication and authorization
- **Monitoring**: Prometheus + Grafana (inherited from CS1)
- **VPN Access**: OpenVPN for secure remote access
- **Network**: Multi-AZ deployment across eu-central-1a and eu-central-1b

## Prerequisites

- AWS CLI configured with `student` profile
- Terraform >= 1.6.0
- kubectl
- AWS Cognito configured for user authentication

## Quick Start

### 1. Clone and Setup

\`\`\bash
git clone https://github.com/YOUR_USERNAME/cs3-ma-nca-infrastructure.git
cd cs3-ma-nca-infrastructure
\`\`\`

### 2. Initialize Terraform

\`\`\`bash
terraform init
\`\`\`

### 3. Deploy Infrastructure

\`\`\`bash
terraform plan
terraform apply
\`\`\`

### 4. Configure kubectl

\`\`\`bash
aws eks update-kubeconfig --region eu-central-1 --name cs3-employee-platform --profile student
kubectl get nodes
\`\`\`

### 5. Get Database Credentials

\`\`\`bash
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw employee_db_secret_arn) \
  --query SecretString --output text --profile student | jq .
\`\`\`

## Project Structure

\`\`\`
cs3-ma-nca-infrastructure/
├── provider.tf                  # AWS & Kubernetes providers
├── variables.tf                 # CS1 variables (inherited)
├── cs3-variables.tf            # CS3-specific variables
├── network.tf                   # CS1 VPC (inherited)
├── cs3-network.tf              # EKS subnets
├── security.tf                  # CS1 security groups (inherited)
├── cs3-security-groups.tf      # EKS security groups
├── cs3-eks.tf                  # EKS cluster & node group
├── cs3-eks-iam.tf              # IAM roles for EKS
├── cs3-rds.tf                  # Employee database
├── cs3-identity.tf             # AWS Cognito
├── cs3-outputs.tf              # CS3 outputs
├── monitoring-stack.tf          # Monitoring (inherited from CS1)
├── monitoring.tf                # CloudWatch (inherited from CS1)
├── openvpn.tf                   # VPN (inherited from CS1)
├── route53.tf                   # DNS (inherited from CS1)
└── .github/workflows/           # CI/CD pipeline
    └── terraform.yml
\`\`\`

## CI/CD Pipeline

The project uses GitHub Actions for automated deployment:

- **Pull Requests**: Automatic `terraform plan` with results posted as PR comment
- **Main Branch**: Automatic `terraform apply` on push to main

## Network Architecture

- **VPC CIDR**: 10.0.0.0/16
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24 (CS1 ALB, NAT)
- **Private Web**: 10.0.10.0/24, 10.0.11.0/24 (CS1 web servers)
- **Database**: 10.0.20.0/24, 10.0.21.0/24 (CS1 database)
- **Monitoring**: 10.0.30.0/24 (CS1 monitoring)
- **EKS Private**: 10.0.40.0/24, 10.0.41.0/24 (EKS nodes)
- **EKS Public**: 10.0.50.0/24, 10.0.51.0/24 (EKS load balancers)
- **Employee DB**: 10.0.60.0/24, 10.0.61.0/24 (Employee database)
- **VPN**: 10.8.0.0/24 (OpenVPN clients)

## Access Methods

### VPN Access

\`\`\`bash
# Download VPN config
terraform output -raw openvpn_config > client.ovpn

# Connect
sudo openvpn client.ovpn
\`\`\`

### EKS Access

\`\`\`bash
# Configure kubectl
aws eks update-kubeconfig --region eu-central-1 --name cs3-employee-platform --profile student

# Verify access
kubectl get nodes
kubectl get pods --all-namespaces
\`\`\`

### Database Access

\`\`\`bash
# Via VPN
psql -h employee-db.cs1.local -U admin -d employeedb
\`\`\`

## Cost Optimization

- EKS: t3.medium nodes (2 nodes minimum)
- RDS: db.t3.micro (can scale to Multi-AZ for production)
- NAT: Using NAT instance instead of NAT Gateway (90% cost savings)
- EBS: gp3 volumes with auto-scaling

**Estimated Monthly Cost**: ~€100-150

## Security

- Zero Trust Architecture implementation
- Network micro-segmentation with security groups
- Private subnets for all workloads
- VPN-only access to internal services
- AWS Cognito for centralized authentication
- Secrets Manager for credential management
- Encrypted RDS storage
- Pod Security Policies enabled

## Monitoring

Access Grafana via VPN:
\`\`\`
http://grafana.cs1.local:3000
Username: admin
Password: admin123
\`\`\`

## Troubleshooting

### EKS Nodes Not Joining

\`\`\`bash
kubectl get nodes
aws eks describe-cluster --name cs3-employee-platform --profile student
\`\`\`

### Database Connection Issues

\`\`\`bash
# Check security groups
aws ec2 describe-security-groups --filters "Name=group-name,Values=*employee-db*" --profile student

# Test DNS resolution (from VPN)
nslookup employee-db.cs1.local
\`\`\`

### VPN Issues

\`\`\`bash
# Check OpenVPN logs
ssh ec2-user@<openvpn-ip> -i ~/.ssh/your-key.pem
sudo tail -f /var/log/openvpn.log
\`\`\`

## Next Steps

1. Deploy AWS Load Balancer Controller
2. Deploy Employee Portal application
3. Configure employee automation Lambda functions
4. Create test users in Cognito User Pool
5. Create Kubernetes namespaces and RBAC policies

## Author

Sonny - CS3-MA-NCA
Fontys University of Applied Sciences

## License

This project is for educational purposes only.
\`\`\`

---

**That's everything! You now have:**

✅ Complete Terraform infrastructure for CS3  
✅ GitHub-hosted CI/CD workflow  
✅ Detailed README  
✅ Setup instructions  

**Next steps:**

1. Copy the files from CS1 to CS3 repo
2. Add the new CS3 Terraform files I provided
3. Create the new S3 bucket for state
4. Add GitHub Secrets (AWS credentials + DB password)
5. Push to GitHub and let the pipeline run!

Want me to help with any specific part of the setup?