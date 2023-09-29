data "aws_route53_zone" "zone" {
  name     = "${var.dns_zone_name}"
}

data "aws_lb" "existing_alb" {
  name = "k8s-eoapi-vectorin-6f3b1773b5"
}

data "aws_lb_listener" "existing_listener" {
  load_balancer_arn = data.aws_lb.existing_alb.arn
  port              = 443
}


resource "aws_acm_certificate" "cert" {
  domain_name               = "*.${data.aws_route53_zone.zone.name}"
  validation_method         = "DNS"
  tags                      = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "subdomain_record" {
  for_each = { for record in var.dns_records: record.dns_subdomain => record }

  name     = "${each.value.dns_subdomain}.${data.aws_route53_zone.zone.name}"
  zone_id  = data.aws_route53_zone.zone.id
  type     = "A"

  alias {
    name                   = data.aws_lb.existing_alb.dns_name
    zone_id                = data.aws_lb.existing_alb.zone_id
    evaluate_target_health = true
  }

}

resource "aws_lb_listener_certificate" "cert" {
  listener_arn    = data.aws_lb_listener.existing_listener.arn
  certificate_arn = aws_acm_certificate.cert.arn
}