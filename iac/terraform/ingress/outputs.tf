output "kibana_public_url" {
  description = "Public URL for Kibana through the ALB Ingress: HTTPS on kibana_hostname when set, otherwise HTTP on the ALB hostname (null in production mode only)"
  value = (
    local.use_domain ? "https://${var.kibana_hostname}" :
    local.use_self_signed ? "https://${var.kibana_alb_hostname}" :
    local.enabled ? "http://${try(kubernetes_manifest.kibana_ingress[0].object.status.loadBalancer.ingress[0].hostname, "pending")}" :
    null
  )
}

output "alb_hostname" {
  description = "ALB DNS name serving the Kibana Ingress (null in production mode or until the ALB is provisioned)"
  value       = local.enabled ? try(kubernetes_manifest.kibana_ingress[0].object.status.loadBalancer.ingress[0].hostname, null) : null
}
