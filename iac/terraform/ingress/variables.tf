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
  description = "Fully qualified public DNS name for Kibana, published by the EKS-managed ExternalDNS (leave unset to use the ALB hostname)"
  type        = string
  default     = null
}

variable "kibana_alb_hostname" {
  description = "ALB DNS name to put on the self-signed certificate, for example k8s-elastic-kibana-xxxx.us-east-2.elb.amazonaws.com. Used only when kibana_hostname is unset. Browsers will warn about this certificate."
  type        = string
  default     = null
}

