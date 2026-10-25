# Access Kibana

Kibana is exposed through an internet-facing AWS Application Load Balancer.
The AWS Load Balancer Controller and ExternalDNS run in `kube-system`; the
Ingress runs in `elastic-stack` because an Ingress can only route to a Service
in its own namespace. The ALB terminates client TLS with ACM and forwards
HTTPS to ECK's private `ClusterIP` Kibana service. Elasticsearch remains
internal to the cluster.

## Deploy the secured endpoint

The ECK values keep the Kibana Service private. Apply the ECK root first, then
apply the ingress root:

```bash
cd iac/terraform/ingress
terraform init
terraform validate
terraform apply \
  -var="cluster_name=$(cd ../eks && terraform output -raw cluster_name)" \
  -var="flavor=medium" \
  -var="kibana_hostname=kibana.example.com" \
  -var="acm_certificate_arn=arn:aws:acm:us-east-2:123456789012:certificate/REPLACE_ME" \
  -var="route53_zone_id=REPLACE_WITH_PUBLIC_HOSTED_ZONE_ID"
```

The ACM certificate must cover `kibana_hostname` and be issued in the same
AWS region as the ALB. ExternalDNS is restricted to the supplied public
hosted zone and creates a TXT ownership record alongside the ALB address.

Verify the controllers, ALB, and DNS record:

```bash
kubectl -n kube-system get deployment aws-load-balancer-controller external-dns
kubectl -n elastic-stack get ingress kibana
aws route53 list-resource-record-sets \
  --hosted-zone-id REPLACE_WITH_PUBLIC_HOSTED_ZONE_ID \
  --query "ResourceRecordSets[?Name=='kibana.example.com.']"
```

The existing [kibana-ingress.yaml](./install-config/kibana-ingress.yaml) is a
reference manifest only; do not apply it alongside the Terraform-managed
Ingress.

Do not commit passwords or other credentials. Retrieve the generated `elastic`
password only when needed:

```bash
kubectl -n elastic-stack get secret elasticsearch-es-elastic-user \
  -o=jsonpath='{.data.elastic}' | base64 --decode
echo
```

The password previously printed in this document must be rotated because it
was exposed in repository history or working copies. Prefer creating a
least-privilege Kibana user instead of using `elastic` for routine access.
