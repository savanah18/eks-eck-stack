# EBS CSI Controller Unhealthy

**Date:** 2026-10-23  
**Environment:** `us-east-2`, EKS `1.37`, `emirates-demo-eks-cluster`

## Symptom

After the node networking issue was resolved, the EBS CSI controller remained
unhealthy:

```text
aws-ebs-csi-driver: DEGRADED
InsufficientNumberOfReplicas
```

Both controller pods were initially in `CrashLoopBackOff` with only `1/6`
containers ready. The failing containers included `ebs-plugin`,
`csi-attacher`, `csi-provisioner`, `csi-resizer`, and `csi-snapshotter`.

## Investigation

Check the add-on and controller:

```bash
aws eks describe-addon \
  --region us-east-2 \
  --cluster-name emirates-demo-eks-cluster \
  --addon-name aws-ebs-csi-driver \
  --query 'addon.{status:status,health:health,associations:podIdentityAssociations}' \
  --output json

kubectl -n kube-system get pods \
  -l app=ebs-csi-controller \
  -o wide

kubectl -n kube-system get serviceaccount ebs-csi-controller-sa -o yaml
```

Inspect the EBS controller logs:

```bash
kubectl -n kube-system logs \
  deployment/ebs-csi-controller \
  -c ebs-plugin \
  --tail=100
```

Check existing Pod Identity associations:

```bash
aws eks list-pod-identity-associations \
  --region us-east-2 \
  --cluster-name emirates-demo-eks-cluster \
  --query 'associations[].{namespace:namespace,serviceAccount:serviceAccount,associationId:associationId}' \
  --output table
```

Resolve an association to its role:

```bash
aws eks describe-pod-identity-association \
  --region us-east-2 \
  --cluster-name emirates-demo-eks-cluster \
  --association-id <association-id> \
  --query 'association.{namespace:namespace,serviceAccount:serviceAccount,role:roleArn}' \
  --output json
```

## Evidence

An existing role was present and correctly configured:

```text
Role: emirates-demo-eks-cluster-eks-ebs-csi-role
Policy: AmazonEBSCSIDriverPolicy
Trust principal: pods.eks.amazonaws.com
Trust actions: sts:AssumeRole, sts:TagSession
```

The controller service account was:

```text
Namespace: kube-system
Service account: ebs-csi-controller-sa
```

The controller logs initially reported:

```text
Failed health check
failed to refresh cached credentials
no EC2 IMDS role found
```

The add-on initially reported no service-account role in its direct role field,
but the correct authorization mechanism for this installation is EKS Pod
Identity. The missing piece was the Pod Identity association being absent or
not yet applied when the controller was first checked.

The association was then present:

```text
Association: a-zw8ggfe93hibnhnbg
Role: arn:aws:iam::751686508085:role/emirates-demo-eks-cluster-eks-ebs-csi-role
Namespace: kube-system
Service account: ebs-csi-controller-sa
```

## Root cause

The existing EBS CSI IAM role was not the problem. The EBS CSI controller
initially did not have an effective EKS Pod Identity association to that role,
so it attempted to use EC2 instance metadata credentials. The controller then
failed its AWS `DescribeAvailabilityZones` health check and all dependent CSI
sidecars crashed.

## Remediation

Associate the existing role with the EBS CSI controller service account using
EKS Pod Identity. Do not create a second role or attach the EBS policy to the
node role.

After the association is created or corrected, restart the controller if it
does not automatically roll:

```bash
kubectl -n kube-system rollout restart deployment ebs-csi-controller
kubectl -n kube-system rollout status deployment ebs-csi-controller --timeout=5m
```

The EKS add-on may recreate the controller pods automatically when the
association is changed.

## Validation

```bash
aws eks describe-pod-identity-association \
  --region us-east-2 \
  --cluster-name emirates-demo-eks-cluster \
  --association-id a-zw8ggfe93hibnhnbg \
  --query 'association.{namespace:namespace,serviceAccount:serviceAccount,role:roleArn}' \
  --output json

aws eks describe-addon \
  --region us-east-2 \
  --cluster-name emirates-demo-eks-cluster \
  --addon-name aws-ebs-csi-driver \
  --query 'addon.{status:status,health:health}' \
  --output json

kubectl -n kube-system get pods \
  -l app=ebs-csi-controller \
  -o wide
```

Current healthy result:

```text
Add-on: ACTIVE
Health issues: []
Controller replicas: 2/2 available
Controller pods: 6/6 Ready
```

The EBS CSI node daemonset should also be checked before testing persistent
volume provisioning:

```bash
kubectl -n kube-system get pods \
  -l app=ebs-csi-node \
  -o wide
```
