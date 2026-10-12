# Default VPC + a public subnet. The instance gets a public IPv4 for outbound traffic only
# (~$3.60/mo) — cheaper than a NAT gateway. Nothing listens: the security group has no ingress.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "aws_security_group" "instance" {
  name        = "${var.name}-instance"
  description = "Agent host: no inbound; outbound HTTP/HTTPS only"
  vpc_id      = data.aws_vpc.default.id

  # No ingress blocks. Access is via SSM Session Manager.

  egress {
    description = "HTTPS (LLM APIs, SSM, S3, Telegram, git)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP (package mirrors that redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
