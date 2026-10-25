# Self-signed certificate for the ALB hostname, used when no domain is set.
# Kibana refuses logins over plain HTTP, so the ALB needs an HTTPS listener.
# Browsers will warn that the certificate is not trusted.
# The private key is stored in the Terraform state, which is kept out of git.
resource "tls_private_key" "self_signed" {
  count = local.use_self_signed ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count = local.use_self_signed ? 1 : 0

  private_key_pem       = tls_private_key.self_signed[0].private_key_pem
  validity_period_hours = 8760
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]

  subject {
    common_name = var.kibana_alb_hostname
  }

  dns_names = [var.kibana_alb_hostname]
}

resource "aws_acm_certificate" "self_signed" {
  count = local.use_self_signed ? 1 : 0

  private_key      = tls_private_key.self_signed[0].private_key_pem
  certificate_body = tls_self_signed_cert.self_signed[0].cert_pem
}
