# Terraform Apply Context Timeout During ECK Deployment

**Date:** 2026-10-25  
**Environment:** `us-east-2`, EKS, Terraform-managed ECK

## Symptom

`terraform apply` failed while creating the ECK Stack Helm release:

```text
Error: installation failed

with helm_release.eck_stack,
on eck.tf line 18, in resource "helm_release" "eck_stack":
error validating "":
error validating data: failed to download openapi:
unexpected error when reading response body.
Please retry.
Original error: context deadline exceeded
```

The failure occurred during Helm's client-side validation of the rendered ECK
resources. The Helm provider attempted to read the Kubernetes API OpenAPI
document, but the response did not complete before the request context
deadline.

## Scope

This error does not identify a problem with the Elasticsearch values file,
Elasticsearch resources, PVCs, or pod scheduling. It indicates that the
Terraform Helm provider could not complete an API request to the EKS control
plane.

Possible network-related causes include:

- Intermittent connectivity between the Terraform runner and the EKS API
  endpoint
- An unavailable or slow EKS control plane during cluster creation
- DNS resolution or proxy problems on the Terraform runner
- Public EKS endpoint access restrictions
- Security-group, firewall, VPN, or corporate-network interference
- A Kubernetes API response that is slow while the cluster is becoming ready

## Investigation

Confirm that the current kubeconfig points to the intended cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-2 \
  --name "$(terraform output -raw cluster_name)"

kubectl config current-context
kubectl cluster-info
```

Test basic API and OpenAPI connectivity:

```bash
kubectl version
kubectl get --raw=/version
kubectl get --raw=/openapi/v2 >/dev/null
kubectl get nodes
```

Terraform's Helm and Kubernetes providers use the AWS CLI exec credential
plugin. Confirm that the same AWS identity can obtain a token:

```bash
aws eks get-token \
  --region us-east-2 \
  --cluster-name "$(terraform output -raw cluster_name)"
```

Check the EKS endpoint and whether it is publicly reachable:

```bash
aws eks describe-cluster \
  --region us-east-2 \
  --name "$(terraform output -raw cluster_name)" \
  --query 'cluster.resourcesVpcConfig.{endpointPublicAccess:endpointPublicAccess,endpointPrivateAccess:endpointPrivateAccess,publicAccessCidrs:publicAccessCidrs,endpoint:endpoint}'
```

Check the Helm and ECK state after a partial apply:

```bash
helm list -A
helm status elastic-operator -n elastic-system
helm status eck-stack-medium -n elastic-stack

kubectl -n elastic-system get pods
kubectl -n elastic-stack get pods
kubectl get events -A --sort-by=.lastTimestamp
```

## Resolution

The ECK Helm releases disable only Helm's client-side OpenAPI validation:

```hcl
disable_openapi_validation = true
```

This is configured for both `helm_release.eck_operator` and
`helm_release.eck_stack` in
[`iac/terraform/eks/eck.tf`](../../iac/terraform/eks/eck.tf).

The setting avoids the specific OpenAPI download timeout during Helm
validation. It does not disable Kubernetes API authentication, Kubernetes
resource validation, ECK reconciliation, or Helm readiness waiting.

The releases continue to wait for readiness:

```hcl
wait    = true
timeout = 600
```

for the operator, and:

```hcl
wait    = true
timeout = 1200
```

for the ECK Stack.

After confirming API connectivity, retry:

```bash
cd iac/terraform/eks
terraform apply -var="flavor=medium"
```

## Alternative mitigation: separate Terraform roots

The EKS, ECK, and NetworkPolicy resources are separated into independent
Terraform roots. This avoids initializing Helm or Kubernetes providers while
the EKS cluster is still being created.

Create the infrastructure first:

```bash
cd iac/terraform/eks
terraform apply
```

After the EKS API is reachable, install ECK:

```bash
cd ../eck
terraform init
terraform apply \
  -var="cluster_name=$(cd ../eks && terraform output -raw cluster_name)" \
  -var="flavor=medium"
```

After ECK is healthy, apply the NetworkPolicies:

```bash
cd ../netpol
terraform init
terraform apply \
  -var="cluster_name=$(cd ../eks && terraform output -raw cluster_name)"
```

This also permits a temporary mitigation during intermittent network
conditions: complete the EKS root first, retry the ECK root independently,
and apply `netpol` only after the Elastic resources are healthy. Do not leave
the NetworkPolicy root unapplied permanently.

## Important limitation

Disabling OpenAPI validation is a mitigation for Helm's client-side schema
request. It is not a replacement for fixing an unreachable or unhealthy
Kubernetes API endpoint. If the following commands also time out, investigate
EKS endpoint access and the Terraform runner's network path:

```bash
kubectl get --raw=/version
kubectl get --raw=/openapi/v2 >/dev/null
```

If these commands succeed but the Helm release still fails, inspect Helm and
ECK readiness rather than changing the OpenAPI setting further.

If Terraform reports `cannot create REST client: no client config` for a
`kubernetes_manifest`, verify the AWS CLI exec credential command above and
confirm that the EKS endpoint and certificate are available to Terraform.

## Prevention

- Wait for the EKS control plane and node groups to become ready before
  installing ECK.
- Run `kubectl get nodes` and the OpenAPI connectivity check before
  `terraform apply`.
- Keep Terraform execution on a network that can reach the configured EKS API
  endpoint.
- Avoid running concurrent Terraform applies against the same state.
- Keep the Helm releases' `wait` and readiness timeouts enabled.
- Use Terraform state and Helm status to recover from interrupted applies
  rather than manually creating duplicate releases.

## Validation

- [ ] `kubectl cluster-info` succeeds.
- [ ] `kubectl get --raw=/version` succeeds.
- [ ] `kubectl get --raw=/openapi/v2` completes.
- [ ] `helm status elastic-operator -n elastic-system` is healthy.
- [ ] `helm status eck-stack-medium -n elastic-stack` is healthy.
- [ ] ECK Elasticsearch and Kibana resources report ready status.
- [ ] Terraform completes without a context deadline error.
