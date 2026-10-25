# Fails the plan until the ECK stack has created the Kibana HTTP Service.
data "kubernetes_service_v1" "kibana" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "kibana-kb-http"
    namespace = "elastic-stack"
  }
}

resource "kubernetes_manifest" "kibana_ingress" {
  count = local.enabled ? 1 : 0

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "kibana"
      namespace = "elastic-stack"
      annotations = merge(
        {
          "alb.ingress.kubernetes.io/backend-protocol"     = "HTTPS"
          "alb.ingress.kubernetes.io/healthcheck-path"     = "/login"
          "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTPS"
          "alb.ingress.kubernetes.io/listen-ports"         = local.use_https ? "[{\"HTTP\":80},{\"HTTPS\":443}]" : "[{\"HTTP\":80}]"
          "alb.ingress.kubernetes.io/scheme"               = "internet-facing"
          "alb.ingress.kubernetes.io/success-codes"        = "200-399"
          "alb.ingress.kubernetes.io/target-type"          = "ip"
        },
        local.use_https ? {
          "alb.ingress.kubernetes.io/certificate-arn" = local.certificate_arn
          "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
        } : {},
        local.use_domain ? {
          "external-dns.alpha.kubernetes.io/hostname" = var.kibana_hostname
        } : {}
      )
    }
    spec = {
      ingressClassName = "alb"
      rules = [
        merge(
          {
            http = {
              paths = [{
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = one(data.kubernetes_service_v1.kibana[*].metadata[0].name)
                    port = {
                      number = 5601
                    }
                  }
                }
              }]
            }
          },
          local.use_domain ? { host = var.kibana_hostname } : {}
        )
      ]
    }
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_acm_certificate_validation.kibana,
  ]
}
