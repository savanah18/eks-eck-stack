output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS public Kubernetes API endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "mode" {
  description = "Deployment mode: demo or production"
  value       = var.mode
}

output "is_production" {
  description = "True when Kibana is exposed publicly through the ALB Ingress (with ExternalDNS) instead of a LoadBalancer Service"
  value       = local.is_production
}

output "route53_zone_arn" {
  description = "ARN of the public Route 53 zone (production only)"
  value       = one(aws_route53_zone.public[*].arn)
}

output "route53_zone_id" {
  description = "ID of the public Route 53 zone (production only)"
  value       = one(aws_route53_zone.public[*].zone_id)
}

output "route53_name_servers" {
  description = "Name servers to delegate at your registrar (production only)"
  value       = one(aws_route53_zone.public[*].name_servers)
}