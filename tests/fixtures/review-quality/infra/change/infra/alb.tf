# Security groups for the internet-facing load balancer in front of the public status API.
resource "aws_security_group" "alb" {
  name        = "status-api-alb"
  description = "Status API load balancer"
  vpc_id      = var.vpc_id
}

# The status API is a public endpoint, so HTTPS is intentionally open to the whole internet.
# Nothing else is exposed: plain HTTP is not listened on and targets only accept traffic from the ALB.
resource "aws_vpc_security_group_ingress_rule" "alb_https_ipv4" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anywhere (public API)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_ipv6" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anywhere (public API)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = "::/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_api" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to the API targets only"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.api.id
}

resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = aws_security_group.api.id
  description                  = "API traffic from the load balancer only"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.alb.id
}
