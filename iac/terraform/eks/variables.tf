variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "domain_name" {
  description = "Public domain for the Route 53 hosted zone that Terraform creates in production mode (for example example.com). Delegate the zone's name servers at your registrar."
  type        = string
  default     = null
}

variable "mode" {
  description = "production exposes Kibana through the ALB Ingress root (ingress controller and ExternalDNS); demo exposes it through a LoadBalancer Service"
  type        = string
  default     = "demo"

  validation {
    condition     = contains(["demo", "production"], var.mode)
    error_message = "The mode must be either demo or production."
  }
}