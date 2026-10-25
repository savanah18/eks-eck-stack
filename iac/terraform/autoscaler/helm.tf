resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = var.autoscaler_namespace
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.46.6"

  create_namespace = false
  wait             = true
  timeout          = 600

  set = [
    {
      name  = "autoDiscovery.clusterName"
      value = var.cluster_name
    },
    {
      name  = "awsRegion"
      value = var.region
    },
    {
      name  = "rbac.serviceAccount.name"
      value = var.autoscaler_service_account
    },
    {
      name  = "cloudProvider"
      value = "aws"
    },
    {
      name  = "extraArgs.balance-similar-node-groups"
      value = "true"
    },
    {
      name  = "extraArgs.expander"
      value = "least-waste"
    },
    {
      name  = "extraArgs.skip-nodes-with-local-storage"
      value = "false"
    },
  ]

  depends_on = [
    aws_eks_pod_identity_association.cluster_autoscaler,
  ]
}
