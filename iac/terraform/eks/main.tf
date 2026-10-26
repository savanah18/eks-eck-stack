provider "aws" {
  region = var.region
}

# Filter localzones zones that are not supported
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# External dns addon is only enabled in production mode. It requires an IAM role to be created and associated with the external-dns service account.
locals {
  cluster_name  = "emirates-demo-eks-${random_string.suffix.result}"
  is_production = var.mode == "production"

  # ExternalDNS publishes the Kibana ALB hostname in production only.
  external_dns_addon = local.is_production ? {
    external-dns = {
      most_recent = true

      configuration_values = jsonencode({
        txtOwnerId = local.cluster_name
      })

      namespace_config = {
        namespace = "external-dns"
      }

      pod_identity_association = [{
        role_arn        = aws_iam_role.external_dns[0].arn
        service_account = "external-dns"
      }]
    }
  } : {}
}

resource "random_string" "suffix" {
  length  = 4
  special = false
}

# Create IAM roles for EKS addons that require pod identity association
data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_cni" {
  name               = "${local.cluster_name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Public zone for Kibana and other ingress hostnames. Destroying it breaks the
# registrar delegation, so it is protected from accidental destroy.
resource "aws_route53_zone" "public" {
  count = local.is_production ? 1 : 0

  name = var.domain_name

  lifecycle {
    prevent_destroy = false

    precondition {
      condition     = var.domain_name != null
      error_message = "domain_name is required when mode is production."
    }
  }
}

data "aws_iam_policy_document" "external_dns" {
  count = local.is_production ? 1 : 0

  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]
    resources = [aws_route53_zone.public[0].arn]
  }

  statement {
    actions = [
      "route53:ListHostedZones",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "external_dns" {
  count = local.is_production ? 1 : 0

  name               = "${local.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_role_policy" "external_dns" {
  count = local.is_production ? 1 : 0

  name   = "${local.cluster_name}-external-dns"
  role   = aws_iam_role.external_dns[0].id
  policy = data.aws_iam_policy_document.external_dns[0].json
}

# Create VPC for EKS cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "${local.cluster_name}-vpc"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3) # limit to 3 AZs

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"] # for eks networking
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"] # for load balancers and other public facing resources

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# Create EKS cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = local.cluster_name
  kubernetes_version = "1.36"

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  # Network configuration
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Add ons
  addons = merge({
    coredns = {
      most_recent = true
    }

    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }

    kube-proxy = {
      most_recent = true
    }

    vpc-cni = {
      most_recent    = true
      before_compute = true

      pod_identity_association = [{
        role_arn        = aws_iam_role.vpc_cni.arn
        service_account = "aws-node"
      }]
    }

    aws-ebs-csi-driver = {
      most_recent = true

      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }

  }, local.external_dns_addon)

  # Node group configuration
  eks_managed_node_groups = {
    system = {
      name           = "system"
      subnet_ids     = module.vpc.private_subnets
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      min_size     = 3
      max_size     = 3
      desired_size = 3

      labels = {
        "node-group" = "system"
        "workload"   = "system"
      }
    }

    elasticsearch_master = {
      name           = "elasticsearch-master"
      subnet_ids     = module.vpc.private_subnets
      instance_types = ["t3.medium"] #originally ["m5.large"]
      capacity_type  = "ON_DEMAND"

      min_size     = 3
      max_size     = 3
      desired_size = 3

      labels = {
        "node-group"         = "eck-stack"
        "workload"           = "elasticsearch"
        "elasticsearch-role" = "master"
      }
    }

    elasticsearch_hot = {
      name           = "elasticsearch-hot"
      subnet_ids     = module.vpc.private_subnets
      instance_types = ["m5.large"] #originally ["m5.xlarge"]
      capacity_type  = "ON_DEMAND"

      min_size     = 3
      max_size     = 4
      desired_size = 3

      # Replace one node at a time without launching a surge node. The account's
      # On-Demand vCPU quota has no room for surge capacity right now.
      update_config = {
        max_unavailable = 1
      }

      labels = {
        "node-group"         = "eck-stack"
        "workload"           = "elasticsearch"
        "elasticsearch-role" = "hot"
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"               = "true"
        "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      }
    }
  }

  tags = {
    "org"         = "emirates"
    "environment" = "demo"
  }

}
