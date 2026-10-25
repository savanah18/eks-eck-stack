# VPC CNI Not Ready

**Date:** 2026-10-23  
**Environment:** `us-east-2`, EKS `1.37`, `emirates-demo-eks-cluster`

## Symptom

New compute nodes remained `NotReady` with:

```text
NetworkReady=false
reason: NetworkPluginNotReady
message: Network plugin returns error: cni plugin not initialized
```

The AWS Console initially showed the VPC CNI add-on as active, but the
detailed add-on health was:

```text
status: DEGRADED
code: InsufficientNumberOfReplicas
```

Both `aws-node` pods were running but only `1/2` containers were ready and
were repeatedly restarting.

## Investigation

Check node and CNI readiness:

```bash
kubectl get nodes -o wide

kubectl -n kube-system get pods \
  -l k8s-app=aws-node \
  -o wide

kubectl -n kube-system get daemonset aws-node -o wide
```

Check the AWS add-on health:

```bash
aws eks describe-addon \
  --region us-east-2 \
  --cluster-name emirates-demo-eks-cluster \
  --addon-name vpc-cni \
  --query 'addon.{status:status,version:addonVersion,health:health,role:serviceAccountRoleArn}' \
  --output json
```

Inspect CNI events and logs:

```bash
kubectl -n kube-system get events \
  --sort-by='.lastTimestamp' \
  | grep -E 'aws-node|MissingIAM|Unauthorized|cni|Failed|Unhealthy'

kubectl -n kube-system logs <aws-node-pod> -c aws-node --previous
```

Inspect the service account and node-role policies:

```bash
kubectl -n kube-system get serviceaccount aws-node -o yaml

aws iam list-attached-role-policies \
  --role-name emirates-demo-eks-cluster-eks-node-role
```

## Evidence

Kubernetes events reported:

```text
MissingIAMPermissions
Unauthorized operation: failed to call ec2:DescribeNetworkInterfaces
```

The VPC CNI add-on had no dedicated service-account role:

```text
serviceAccountRoleArn: null
```

The node role had:

```text
AmazonEKSWorkerNodePolicy
AmazonEC2ContainerRegistryPullOnly
```

It did not have `AmazonEKS_CNI_Policy`. The `aws-node` service account also
had no IAM role annotation.

## Root cause

The VPC CNI lacked IAM permission to call the EC2 APIs required for pod
networking, including `ec2:DescribeNetworkInterfaces`. The add-on being
installed or initially displayed as `ACTIVE` did not mean that its containers
were healthy.

The node `NotReady` status was a consequence of the CNI failure, not a normal
startup delay.

## Remediation

The immediate recovery option is to attach the AWS-managed CNI policy to the
existing node role:

```bash
aws iam attach-role-policy \
  --region us-east-2 \
  --role-name emirates-demo-eks-cluster-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
```

Restart the CNI daemonset after the permission is available:

```bash
kubectl -n kube-system rollout restart daemonset aws-node
kubectl -n kube-system rollout status daemonset aws-node --timeout=5m
```

For the long-term configuration, use a dedicated IAM role for the VPC CNI
through EKS Pod Identity or IRSA instead of adding CNI permissions to the
general node role.

## Validation

```bash
aws eks describe-addon \
  --region us-east-2 \
  --cluster-name emirates-demo-eks-cluster \
  --addon-name vpc-cni \
  --query 'addon.{status:status,health:health}' \
  --output json

kubectl -n kube-system get pods -l k8s-app=aws-node -o wide
kubectl get nodes -o wide
```

Expected results:

- VPC CNI status is `ACTIVE` with no health issues.
- Every `aws-node` pod is fully ready.
- Nodes report `Ready`.
- The `MissingIAMPermissions` event stops recurring.
- Core system pods can be scheduled and start successfully.
