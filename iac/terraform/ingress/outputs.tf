output "kibana_public_url" {
  description = "Public HTTPS URL for Kibana through the ALB Ingress (null in production mode)"
  value       = local.enabled ? "https://${var.kibana_hostname}" : null
}

output "alb_hostname" {
  description = "ALB DNS name serving the Kibana Ingress (null in production mode or until the ALB is provisioned)"
  value       = local.enabled ? try(kubernetes_manifest.kibana_ingress[0].object.status.loadBalancer.ingress[0].hostname, null) : null
}
