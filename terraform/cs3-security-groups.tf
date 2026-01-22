# ============================================================================
# CS3 Security Groups - EKS and Employee Services
# ============================================================================

# Security Group for EKS Control Plane
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.project_name}-eks-cluster-"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-eks-cluster-sg"
      Environment = var.environment
    }
  )
}

# EKS Cluster - Allow inbound from worker nodes
resource "aws_security_group_rule" "eks_cluster_ingress_workstation_https" {
  description       = "Allow workstation to communicate with the cluster API Server"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"] # VPC CIDR
  security_group_id = aws_security_group.eks_cluster.id
}

# EKS Cluster - Allow VPN access
resource "aws_security_group_rule" "eks_cluster_ingress_vpn" {
  description       = "Allow VPN clients to access cluster API"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["10.8.0.0/24"] # VPN CIDR
  security_group_id = aws_security_group.eks_cluster.id
}

# EKS Cluster - Allow outbound
resource "aws_security_group_rule" "eks_cluster_egress" {
  description       = "Allow cluster egress"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_cluster.id
}

# Security Group for EKS Worker Nodes
resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.project_name}-eks-nodes-"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.cs3_tags,
    {
      Name                                            = "${var.project_name}-eks-nodes-sg"
      Environment                                     = var.environment
      "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
    }
  )
}

# Node to Node communication
resource "aws_security_group_rule" "eks_nodes_internal" {
  description              = "Allow nodes to communicate with each other"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_nodes.id
}

# Control plane to nodes
resource "aws_security_group_rule" "eks_nodes_cluster_ingress" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
}

# Nodes to control plane
resource "aws_security_group_rule" "eks_cluster_ingress_node_https" {
  description              = "Allow pods to communicate with the cluster API Server"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
}

# Nodes egress
resource "aws_security_group_rule" "eks_nodes_egress" {
  description       = "Allow nodes all egress"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_nodes.id
}

# Allow SSH from VPN (for debugging)
resource "aws_security_group_rule" "eks_nodes_ssh_vpn" {
  description       = "Allow SSH from VPN for node debugging"
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["10.8.0.0/24"]
  security_group_id = aws_security_group.eks_nodes.id
}

# Security Group for Employee Database
resource "aws_security_group" "employee_db" {
  name_prefix = "${var.project_name}-employee-db-"
  description = "Security group for employee database"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-employee-db-sg"
      Environment = var.environment
    }
  )
}

# Allow EKS nodes to access employee database
resource "aws_security_group_rule" "employee_db_from_eks" {
  description              = "Allow EKS nodes to access employee database"
  type                     = "ingress"
  from_port                = 5432 # PostgreSQL
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.employee_db.id
}

# Allow VPN access to database (for management)
resource "aws_security_group_rule" "employee_db_from_vpn" {
  description       = "Allow VPN access for database management"
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["10.8.0.0/24"]
  security_group_id = aws_security_group.employee_db.id
}

# Allow monitoring to access database
resource "aws_security_group_rule" "employee_db_from_monitoring" {
  description              = "Allow monitoring to access employee database"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
  security_group_id        = aws_security_group.employee_db.id
}