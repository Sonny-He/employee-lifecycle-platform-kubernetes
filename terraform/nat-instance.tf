# ============================================================================
# NAT Instance for Cost-Effective Outbound Internet Access
# ============================================================================

resource "aws_instance" "nat_instance" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public[0].id
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.nat_instance.id]

  # CRITICAL: Disable source/destination check for NAT functionality
  source_dest_check = false

  user_data = base64encode(file("${path.module}/nat_user_data.sh"))

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = {
    Name        = "${var.project_name}-nat-instance"
    Environment = var.environment
    Purpose     = "NAT"
  }
}