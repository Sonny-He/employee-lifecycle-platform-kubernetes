# Private Hosted Zone for internal VPC DNS
resource "aws_route53_zone" "private" {
  name = var.internal_domain_name

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name        = "${var.project_name}-private-zone"
    Environment = var.environment
    Type        = "Private"
  }
}

# Internal DNS record for monitoring server
resource "aws_route53_record" "monitoring" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "monitoring.${var.internal_domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.monitoring.private_ip]
}

# Internal DNS record for NAT instance
resource "aws_route53_record" "nat" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "nat.${var.internal_domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.nat_instance.private_ip]
}