variable "cluster_name" {
  description = "Existing EKS cluster name"
  type        = string
}

variable "region" {
  description = "AWS region containing the EKS cluster"
  type        = string
  default     = "us-east-2"
}

variable "flavor" {
  description = "ECK Stack sizing flavor used to select the values file"
  type        = string
  default     = "medium"

  validation {
    condition     = contains(["small", "medium"], var.flavor)
    error_message = "The flavor must be either small or medium."
  }
}
