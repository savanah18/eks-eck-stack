variable "cluster_name" {
  description = "Existing EKS cluster name"
  type        = string
}

variable "region" {
  description = "AWS region containing the EKS cluster"
  type        = string
  default     = "us-east-2"
}

variable "kibana_hostname" {
  description = "Fully qualified public DNS name for Kibana, published by the EKS-managed ExternalDNS (required when the EKS mode is production)"
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN covering kibana_hostname (required when the EKS mode is production)"
  type        = string
  default     = null
}
