variable "cluster_name" {
  description = "Existing EKS cluster name"
  type        = string
}

variable "region" {
  description = "AWS region containing the EKS cluster"
  type        = string
  default     = "us-east-2"
}

variable "autoscaler_namespace" {
  description = "Namespace for Cluster Autoscaler"
  type        = string
  default     = "kube-system"
}

variable "autoscaler_service_account" {
  description = "Service account used by Cluster Autoscaler"
  type        = string
  default     = "cluster-autoscaler"
}
