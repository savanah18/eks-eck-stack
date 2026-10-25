output "cluster_autoscaler_role_arn" {
  description = "IAM role used by Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}
