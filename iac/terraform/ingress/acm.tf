# Certificate for the Kibana hostname, validated by DNS in the zone the eks root creates.
# DNS validation only succeeds once the parent domain delegates to that zone's name servers.
# Terraform cannot create that delegation here, so set it at the registrar first.
# Skipped when kibana_hostname is not set, which serves Kibana over HTTP on the ALB hostname.
resource "aws_acm_certificate" "kibana" {
  count = local.use_domain ? 1 : 0

  domain_name       = var.kibana_hostname
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "kibana_validation" {
  for_each = local.use_domain ? {
    for dvo in flatten(aws_acm_certificate.kibana[*].domain_validation_options) : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.terraform_remote_state.eks.outputs.route53_zone_id
}

resource "aws_acm_certificate_validation" "kibana" {
  count = local.use_domain ? 1 : 0

  certificate_arn         = aws_acm_certificate.kibana[0].arn
  validation_record_fqdns = [for record in aws_route53_record.kibana_validation : record.fqdn]
}
