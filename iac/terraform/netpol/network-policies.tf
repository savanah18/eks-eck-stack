locals {
  network_policy_manifests = {
    default_deny_ingress = "${path.module}/../../kubernetes/network-policies/default-deny-ingress.yaml"
    default_deny_egress  = "${path.module}/../../kubernetes/network-policies/default-deny-egress.yaml"
    dns_egress           = "${path.module}/../../kubernetes/network-policies/dns-egress.yaml"
    elasticsearch        = "${path.module}/../../kubernetes/network-policies/elasticsearch.yaml"
    kibana               = "${path.module}/../../kubernetes/network-policies/kibana.yaml"
    metricbeat           = "${path.module}/../../kubernetes/network-policies/metricbeat.yaml"
  }
}

resource "kubernetes_manifest" "network_policy" {
  for_each = local.network_policy_manifests

  manifest = yamldecode(file(each.value))
}
