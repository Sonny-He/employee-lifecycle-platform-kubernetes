# ============================================================================
# CS3 Network - EKS Subnets
# ============================================================================
# This file adds EKS-specific subnets to the existing CS1 VPC
# ============================================================================

# Private Subnets for EKS Nodes (both AZs)
resource "aws_subnet" "eks_private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 40}.0/24" # 10.0.40.0/24, 10.0.41.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    var.cs3_tags,
    {
      Name                                            = "${var.project_name}-eks-private-${count.index + 1}"
      Environment                                     = var.environment
      Type                                            = "Private"
      Purpose                                         = "EKS-Nodes"
      AZ                                              = data.aws_availability_zones.available.names[count.index]
      "kubernetes.io/role/internal-elb"               = "1"
      "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    }
  )
}

# Public Subnets for EKS Load Balancers (if needed, both AZs)
resource "aws_subnet" "eks_public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 50}.0/24" # 10.0.50.0/24, 10.0.51.0/24
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.cs3_tags,
    {
      Name                                            = "${var.project_name}-eks-public-${count.index + 1}"
      Environment                                     = var.environment
      Type                                            = "Public"
      Purpose                                         = "EKS-LoadBalancers"
      AZ                                              = data.aws_availability_zones.available.names[count.index]
      "kubernetes.io/role/elb"                        = "1"
      "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    }
  )
}

# Route Table for EKS Private Subnets (uses existing NAT)
resource "aws_route_table_association" "eks_private" {
  count          = 2
  subnet_id      = aws_subnet.eks_private[count.index].id
  route_table_id = aws_route_table.private.id # Reuse CS1's private route table with NAT
}

# Route Table for EKS Public Subnets
resource "aws_route_table_association" "eks_public" {
  count          = 2
  subnet_id      = aws_subnet.eks_public[count.index].id
  route_table_id = aws_route_table.public.id # Reuse CS1's public route table
}

# Database Subnets for Employee RDS (both AZs)
resource "aws_subnet" "employee_db" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 60}.0/24" # 10.0.60.0/24, 10.0.61.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-employee-db-${count.index + 1}"
      Environment = var.environment
      Type        = "Database"
      Purpose     = "Employee-Database"
      AZ          = data.aws_availability_zones.available.names[count.index]
    }
  )
}

# DB Subnet Group for Employee RDS
resource "aws_db_subnet_group" "employee" {
  name       = "${var.project_name}-employee-db-subnet-group"
  subnet_ids = aws_subnet.employee_db[*].id

  tags = merge(
    var.cs3_tags,
    {
      Name        = "${var.project_name}-employee-db-subnet-group"
      Environment = var.environment
    }
  )
}