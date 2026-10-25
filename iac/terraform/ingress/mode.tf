# The eks root owns the deployment mode. The ALB ingress, its controller and
# ExternalDNS exist only in production. In demo this root creates nothing and
# Kibana is exposed through a LoadBalancer Service instead. Applying eks first
# is required so the is_production output exists.
data "terraform_remote_state" "eks" {
  backend = "local"

  config = {
    path = "${path.module}/../eks/terraform.tfstate"
  }
}

locals {
  enabled = data.terraform_remote_state.eks.outputs.is_production
}
