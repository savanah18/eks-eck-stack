resource "helm_release" "eck_operator" {
  name             = "elastic-operator"
  repository       = "https://helm.elastic.co"
  chart            = "eck-operator"
  namespace        = "elastic-system"
  create_namespace = true

  values = [
    file("${path.module}/values/eck-operator-values-system.yaml")
  ]

  # ECK installs CRDs and the Kubernetes OpenAPI endpoint can time out while
  # the EKS control plane is becoming ready. ECK still validates resources at
  # runtime after the operator is installed.
  disable_openapi_validation = true
  wait                       = true
  timeout                    = 600

}

# Mode is owned by the eks root. Applying eks first is required so this output exists.
data "terraform_remote_state" "eks" {
  backend = "local"

  config = {
    path = "${path.module}/../eks/terraform.tfstate"
  }
}

locals {
  # Production keeps Kibana private for the ALB Ingress root. Demo exposes it
  # through a LoadBalancer Service. No annotations are set so the existing
  # Classic ELB and its hostname are kept.
  kibana_service_values = yamlencode({
    eck-kibana = {
      http = {
        service = {
          spec = {
            type = data.terraform_remote_state.eks.outputs.is_production ? "ClusterIP" : "LoadBalancer"
          }
        }
      }
    }
  })
}

resource "helm_release" "eck_stack" {
  name             = "eck-stack-${var.flavor}"
  repository       = "https://helm.elastic.co"
  chart            = "eck-stack"
  namespace        = "elastic-stack"
  create_namespace = true

  values = [
    file("${path.module}/values/eck-stack-values-eks-demo-${var.flavor}.yaml"),
    local.kibana_service_values,
  ]

  # Avoid a client-side OpenAPI download timeout when validating ECK CRs.
  disable_openapi_validation = true
  wait                       = true
  timeout                    = 1200

  depends_on = [helm_release.eck_operator]
}
