variable "cluster_name" {
  description = "Existing EKS cluster name"
  type        = string
}

variable "region" {
  description = "AWS region containing the EKS cluster"
  type        = string
  default     = "us-east-2"
}
