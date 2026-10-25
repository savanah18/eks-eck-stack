# EKS Node Creation Failure

**Date:** 2026-10-23  
**Environment:** `us-east-2`, EKS `1.37`, `emirates-demo-eks-cluster`

## Symptom

Both managed node groups failed with:

```text
NodeCreationFailure
Instances failed to join the kubernetes cluster
```

Affected node groups:

- `emirates-demo-eks-cluster-node-group-1`
- `emirates-demo-eks-cluster-node-group-2`

Both used `amiType: CUSTOM` and the same launch template:

```text
emirate-demo-eks-cluster-launch-template
lt-0ff0f33c424b87ab0, version 1
```

## Investigation

Inspect the node group and launch template:

```bash
aws eks describe-nodegroup \
  --cluster-name emirates-demo-eks-cluster \
  --nodegroup-name <node-group-name> \
  --query 'nodegroup.{status:status,amiType:amiType,launchTemplate:launchTemplate,health:health,nodeRole:nodeRole}' \
  --output json

aws ec2 describe-launch-template-versions \
  --launch-template-id <launch-template-id> \
  --versions <version> \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.{image:ImageId,instance:InstanceType,profile:IamInstanceProfile,userData:UserData,network:NetworkInterfaces}' \
  --output json
```

Inspect a failed instance:

```bash
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].{id:InstanceId,image:ImageId,state:State,subnet:SubnetId,profile:IamInstanceProfile}' \
  --output json

aws ec2 get-console-output \
  --instance-id <instance-id> \
  --latest \
  --query Output \
  --output text
```

## Evidence

The custom launch template contained:

```text
ImageId: ami-053ef5d7ebe355f4a
InstanceType: t3.small
UserData: null
IamInstanceProfile: null
```

The AMI was a general-purpose Amazon Linux 2023 image, not an EKS-optimized
node image. Instances booted normally, but their console output contained no
EKS bootstrap, `nodeadm` configuration, or kubelet startup.

Supporting checks were healthy:

- Instances reached `running` and passed EC2 reachability checks.
- The generated EKS instance profiles used the expected node role.
- The node role had an EKS access entry with `system:nodes`.
- VPC CNI and kube-proxy were `ACTIVE`.
- Node subnets had working NAT routes.

The SSM agent credential warning was unrelated to EKS registration; it only
indicated that Systems Manager Default Host Management was not configured.

## Root cause

The custom AMI and launch template did not provide the bootstrap configuration
required to start kubelet and register nodes with the cluster. Since both node
groups used the same template, both failed identically.

## Remediation

Create replacement managed node groups using:

```text
AMI type: Amazon Linux 2023 (AL2023_x86_64_STANDARD)
Instance type: t3.small
```

Do not select `Custom AMI` or reuse the broken launch template. EKS will select
the correct regional AMI and provide the required bootstrap configuration.

The EKS-optimized AMI available in the console was:

```text
AMI: ami-024ec5a4fea7b44a8
Name: amazon-eks-node-al2023-x86_64-standard-1.37-v20260930
Release date: 2026-09-30
Owner: 602401143452
```

This is an AWS-owned EKS-optimized Amazon Linux 2023 image for Kubernetes
`1.37` and `x86_64`. Confirm that it is `available` in `us-east-2` before
using it. The AMI ID can change as AWS publishes newer releases.

For a managed node group, selecting
`Amazon Linux 2023 (AL2023_x86_64_STANDARD)` remains preferable because EKS
selects the compatible AMI automatically. If selecting an AMI manually, use
the available AMI above rather than the unrelated general-purpose AMI
`ami-053ef5d7ebe355f4a`.

Check the current AWS recommendation dynamically:

```bash
aws ssm get-parameter \
  --region us-east-2 \
  --name /aws/service/eks/optimized-ami/1.37/amazon-linux-2023/x86_64/standard/recommended/image_id \
  --query 'Parameter.Value' \
  --output text
```

If the SSM result differs from the AMI visible in the console, prefer the EKS
managed node-group AMI selection and record the selected ID and release in
this journal.

If a custom AMI is required, it must include compatible AL2023 `nodeadm` user
data, the correct instance profile, and working network access.

## Console procedure

1. Open **EKS → Clusters → `emirates-demo-eks-cluster`**.
2. Open **Compute → Add node group**.
3. Select `emirates-demo-eks-cluster-eks-node-role`.
4. Select **Amazon Linux 2023 (AL2023_x86_64_STANDARD)**.
5. Select `t3.small`, the required subnets, and scaling values.
6. Create the node group and wait for `ACTIVE`.
7. Verify the new nodes before deleting the failed groups.

When using the EC2 AMI picker, do not select a generic **Amazon Linux 2023**
Community AMI. Verify the exact EKS AMI ID, owner, architecture, and
Kubernetes version.

## Validation

```bash
aws eks describe-nodegroup \
  --cluster-name emirates-demo-eks-cluster \
  --nodegroup-name <replacement-node-group> \
  --query 'nodegroup.{status:status,health:health,amiType:amiType,release:releaseVersion}' \
  --output json

kubectl get nodes -o wide
kubectl get pods -A
```

Expected results:

- The node group is `ACTIVE` with no health issues.
- Nodes appear as `Ready`.
- Core system pods are healthy.
- Failed node groups can be removed after successful verification.
