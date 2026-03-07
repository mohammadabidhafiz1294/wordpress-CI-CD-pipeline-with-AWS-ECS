resource "aws_route53_zone" "wordpress" {
  name = var.domain_name

  tags = {
    Name = "wordpress-zone"
  }
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_www" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_admin" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "admin.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_ns" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.domain_name
  type    = "NS"

  ttl = 172800

  records = aws_route53_zone.wordpress.name_servers
}
