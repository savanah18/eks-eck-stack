# Kibana ALB Ingress Setup: Chart Timeout, IAM Gap, and Domain Dependency

**Date:** 2026-10-26  
**Environment:** `us-east-2`, EKS `1.36`, cluster `emirates-demo-eks-9HEI`, `mode = production`  
**Status:** Resolved for the demo over HTTP. HTTPS on a custom domain is not set up.

## Symptoms

1. `terraform apply` of the ingress root failed while downloading the ALB controller chart:

   ```text
   Error locating chart
   Unable to locate chart aws-load-balancer-controller: Get
   "https://aws.github.io/eks-charts/aws-load-balancer-controller-3.6.2.tgz":
   context deadline exceeded (Client.Timeout exceeded while awaiting headers)
   ```

2. After the cluster came up, the Kibana Ingress never got an address:

   ```text
   Warning  FailedBuildModel  ingress  Failed build model due to ingress:
   elastic-stack/kibana: operation error ACM: ListCertificates ...
   AccessDeniedException: ... is not authorized to perform: acm:ListCertificates
   ```

3. `https://kibana.demo.eks-eck-sre.emirates` could not be reached.

## Investigation

Chart download, from this machine:

```bash
curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' \
  https://aws.github.io/eks-charts/index.yaml
```

The repository returned HTTP 200 in under a second, so the timeout was transient. It came from the machine running Terraform, not from this session's network.

Ingress and certificate state:

```bash
kubectl -n elastic-stack describe ingress kibana
aws acm list-certificates --region us-east-2
aws route53 list-hosted-zones
```

Findings:

- The ALB controller's role had no ACM or server-certificate read actions, so it could not discover the certificate.
- No ACM certificate existed in `us-east-2`. The repo never created one.
- The hosted zone `demo.eks-eck-sre.emirates` existed, but nothing published its name servers. `dig NS demo.eks-eck-sre.emirates @8.8.8.8` returned nothing.
- The parent domain `eks-eck-sre.emirates` was not in this account's Route 53, not registered in Route 53 Domains, and had no public NS records. It had been chosen as a placeholder, so no one could delegate it.
- A `dmeo.demo.eks-eck-sre.emirates` NS record shown in the console was not in zone `Z02085753K6P1KJ0GCQR5`. It was likely in another zone or view, so nothing was deleted.

## Root cause

- **Chart timeout:** transient network failure on the machine running Terraform.
- **Ingress failure:** missing IAM actions in `ingress/iam.tf`, which is a bug in the repo.
- **Unreachable HTTPS:** the domain chosen for the demo was not owned, so DNS delegation and ACM validation were impossible. The HTTPS design depended on a domain the user did not control.
- **Self-signed certificate SAN bootstrap:** the ALB hostname is assigned only after the Ingress creates the ALB, but the HTTPS listener needs a certificate before it can be created. The certificate SAN therefore cannot be populated with the ALB hostname during the initial apply.

## No-cost HTTPS workaround

A registered domain is not required for a demo. Use the AWS-generated ALB hostname and apply in two phases:

1. Set both `kibana_hostname` and `kibana_alb_hostname` to `null`, then apply. The Ingress creates the ALB over HTTP.
2. Read the hostname:

   ```bash
   kubectl -n elastic-stack get ingress kibana \
     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
   ```

3. Set `kibana_alb_hostname` to that exact hostname, without `https://`, a port, or a path.
4. Apply again. Terraform creates the self-signed certificate with the ALB hostname in its SAN and adds the HTTPS listener.

The browser will report that the certificate is not trusted because it is self-signed, but the hostname/SAN will match. If the ALB is later recreated and receives a different hostname, repeat the two-phase process. This avoids domain registration and ACM DNS validation, but is not suitable for production.

## Changes

- `ingress/iam.tf`: added `acm:ListCertificates`, `acm:DescribeCertificate`, `iam:ListServerCertificates` and `iam:GetServerCertificate` to the ALB controller policy.
- `ingress/acm.tf`: the ACM certificate and its DNS validation records are created only when `kibana_hostname` is set.
- `ingress/kibana.tf`: without a hostname, the Ingress serves HTTP on port 80 with no certificate, host rule or ExternalDNS annotation. The backend stays HTTPS to ECK's internal Kibana Service.
- `ingress/outputs.tf`: `kibana_public_url` returns `https://<host>` when a hostname is set, otherwise `http://<alb-hostname>`.
- `eks/outputs.tf`: new `route53_zone_id` output, applied with `mode = production`.

## Validation

```bash
cd iac/terraform/ingress
terraform plan -var="cluster_name=emirates-demo-eks-9HEI"
terraform apply <saved-plan>

kubectl -n elastic-stack get ingress kibana -o wide
curl -s -o /dev/null -w 'http=%{http_code}\n' http://<alb-hostname>/login
aws elbv2 describe-target-health --target-group-arn <kibana-target-group>
```

Results:

- The plan showed 2 in-place changes and 0 destroys: the IAM policy and the Ingress.
- The apply succeeded. The Ingress shows `ADDRESS = k8s-elastics-kibana-c18b4d69db-1279129149.us-east-2.elb.amazonaws.com` and `Successfully reconciled`.
- `http://<alb-hostname>/login` returned HTTP 200.
- Both Kibana targets are `healthy`.
- The `alb_hostname` output was not yet in the Terraform state at the time of writing. A plan is needed to add it.

## Remaining work

- **HTTPS:** requires a domain the user controls. Either register one through Route 53, which creates the zone automatically, or delegate a subdomain of a domain they already own. Then set `kibana_hostname` and rerun the ingress root, which creates the certificate and records.
- **Security:** the ALB serves HTTP, so Kibana logins are not encrypted in transit. Use only for the demo.
- **Chart version:** the ALB controller and ExternalDNS charts are not pinned, so applies may download different versions over time.
- **Output state:** confirm `alb_hostname` appears after a plan and apply.
- **Old resources:** check for leftover ExternalDNS resources and the unused zone. The Route 53 zone has `prevent_destroy` set.
