# The eks root owns the deployment mode. The ALB ingress, its controller and
# ExternalDNS exist only in production. In demo this root creates nothing and
# Kibana is exposed through a LoadBalancer Service instead. Applying eks first
# is required so the is_production output exists.
data "terraform_remote_state" "eks" {
  backend = "local"

  config = {
    path = "${path.module}/../eks/terraform.tfstate"
  }
}

locals {
  enabled = data.terraform_remote_state.eks.outputs.is_production

  # HTTPS with an ACM certificate and a DNS record needs a hostname. Without one the
  # ALB serves HTTP on its AWS-generated hostname.
  use_domain = local.enabled && var.kibana_hostname != null

  # Without a domain, a self-signed certificate for the ALB hostname gives an HTTPS
  # listener, which Kibana needs for login.
  use_self_signed = local.enabled && !local.use_domain && var.kibana_alb_hostname != null

  use_https = local.use_domain || local.use_self_signed

  certificate_arn = local.use_domain ? one(aws_acm_certificate_validation.kibana[*].certificate_arn) : one(aws_acm_certificate.self_signed[*].arn)
}
