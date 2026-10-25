# Elasticsearch Hot Node Group Update Blocked by EC2 vCPU Quota

**Date:** 2026-10-25 (16:33–16:51 UTC; journaled 2026-10-26)  
**Environment:** `us-east-2`, EKS `1.36`, cluster `emirates-demo-eks-3SEf`  
**Status:** Open

## Symptom

`terraform apply` of the EKS root changed the `elasticsearch_hot` node group's
launch template to version 2, which started a rolling update. The update
failed:

```text
Update type:  VersionUpdate
Status:       Failed
Error:        NodeCreationFailure
Message:      Couldn't proceed with upgrade process as new nodes are not joining
              node group elasticsearch-hot-82c763f4e024a3db3b001af101
Params:       LaunchTemplateVersion = 2
```

The node group itself stayed `ACTIVE` with three healthy `m5.xlarge` nodes on
launch template version 1.

## Investigation

Node group health and update history:

```bash
aws eks describe-nodegroup --name emirates-demo-eks-3SEf \
  --nodegroup-name elasticsearch-hot-82c763f4e024a3db3b001af101 --region us-east-2
aws eks list-updates --name emirates-demo-eks-3SEf \
  --nodegroup-name elasticsearch-hot-82c763f4e024a3db3b001af101 --region us-east-2
aws eks describe-update --name emirates-demo-eks-3SEf \
  --nodegroup-name elasticsearch-hot-82c763f4e024a3db3b001af101 \
  --update-id 35dadcf2-1798-32ae-b735-84c5173e46fd --region us-east-2
```

Launch template versions (the diff between them is tags only):

```bash
aws ec2 describe-launch-template-versions --region us-east-2 \
  --launch-template-id lt-08d59bf7c01d05d13 --versions 1 2
```

Auto Scaling activity for the group, which showed the real launch error:

```bash
aws autoscaling describe-scaling-activities --region us-east-2 \
  --auto-scaling-group-name eks-elasticsearch-hot-82c763f4e024a3db3b001af101-d6d0b959-4a99-2d4f-8522-699e2f8be0e1 \
  --max-items 15
```

Quota and usage:

```bash
aws service-quotas get-service-quota --region us-east-2 --service-code ec2 \
  --quota-code L-1216C47A
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=instance-state-name,Values=pending,running"
```

## Evidence

- Every launch attempt from 16:33 to 16:51 UTC failed with:

  ```text
  Could not launch On-Demand Instances. VcpuLimitExceeded - You have requested
  more vCPU capacity than your current vCPU limit of 32 allows for the instance
  bucket that the specified instance type belongs to.
  ```

- The group had been scaled from 3 to 6 during that window, and the rolling
  update to launch template v2 needed surge capacity on top of that. Nothing
  launched, so EKS reported the nodes as not joining.
- The quota `L-1216C47A` (Running On-Demand Standard instances) is **32 vCPU**
  in `us-east-2`.
- Running instances count to about **36 vCPU**:
  - `emirates-demo-eks-3SEf`: 3× `t3.medium` (system), 3× `m5.xlarge`
    (elasticsearch-hot), 3× `m5.large` (elasticsearch-master), 24 vCPU.
  - `emirates-demo-eks-cluster` (the old cluster from
    [node-creation-failure](node-creation-failure.md)): 2× `t3.medium`
    (`node-group-2`) and 3× `m5.large` (`node-group-3`), 10 vCPU.
  - One untagged `t3.micro` (2 vCPU), `i-0c6973463bf942467`.
- The current Auto Scaling group bounds are min 3, max 3, desired 3. The
  Terraform file on disk now sets `max_size = 4`, which is not yet applied.
- The hot group has no `update_config`, so EKS uses its default surge behaviour.

## Root cause

The account's On-Demand vCPU quota is exhausted by running instances, including
nodes from the old `emirates-demo-eks-cluster`. The hot node group's scale-up
(3 → 6) and the rolling update's surge node both needed EC2 capacity the
account could not provide. The update therefore failed with `NodeCreationFailure`.

This is not the same failure as
[node-creation-failure](node-creation-failure.md). That entry was caused by a
custom AMI with no bootstrap. The error text is the same, so check the
Auto Scaling activity log before assuming either cause.

## Mitigation considered

Lowering `max_size` alone is not a fix:

- It stops the scale-up attempts from 3 to 6, which is the main source of
  failed launches.
- It does not free any vCPU. The account is already at or over 32.
- `max_size = 4` (the current file) still allows a launch of one `m5.xlarge`
  (4 vCPU), which would fail on the same quota.
- A rolling update still needs one surge node, so the update still fails until
  vCPU is freed or the quota is raised.
- `max_size = 3` stops all scale-up, which removes the Elasticsearch hot tier
  headroom the autoscaling design relies on.

## Remediation options (not yet applied)

1. Delete the old cluster `emirates-demo-eks-cluster` and its node groups. This
   frees about 10 vCPU. Confirm nothing in it is needed first.
2. Request a quota increase for `L-1216C47A` in `us-east-2`, for example to 64.
3. Add `update_config { max_unavailable = 1 }` to the hot node group. This lets
   EKS replace a node without surge capacity. It helps the rolling update but
   does not fix the quota.

## Updates

### 2026-10-26 (01:03 +08, 17:03 UTC): node group deleted, update retried

- The operator deleted `emirates-demo-eks-cluster-node-group-3` (3× `m5.large`,
  6 vCPU) from the old cluster. It was `DELETING` when checked. The other old
  groups are still present: `node-group-2` (2× `t3.medium`, desired 2) and
  `node-group-1` (desired 0, no instances).
- A second `VersionUpdate` to launch template v2 (`0c625d8a-225b-3492-90d2-6f83580fa1ef`)
  started at 17:03 UTC and was `InProgress` at last check.
- The hot group's Auto Scaling group still has desired 6 with 3 instances. New
  launches at 17:04 and 17:05 UTC failed with `VcpuLimitExceeded`.
- Estimated usage after group-3 is gone is about 30 vCPU against the 32 limit.
  A surge `m5.xlarge` needs 4 more, which is 34, so the rolling update will
  still fail. Removing `node-group-2` (4 vCPU) would bring usage to about 26
  and leave room for the surge node. The untagged `t3.micro` (2 vCPU) is the
  next candidate.
- The vCPU figures are counted from `describe-instances`, not from the Service
  Quotas usage metric. Confirm with the usage metric before relying on them.

### 2026-10-26 (01:11 +08, 17:11 UTC): group-3 still deleting, max reduced in config

- `node-group-3` was still `DELETING`.
- The operator reduced the hot node group's `max_size` from 6 to 4 in
  `iac/terraform/eks/main.tf`. This is not applied yet. The live ASG still
  shows min 3, max 6, desired 6.
- Launch attempts continued at 17:07 and 17:11 UTC and failed with
  `VcpuLimitExceeded`.
- Running instances are 12, about 30 vCPU: 3× `t3.medium` (system), 3×
  `m5.xlarge` (hot), 3× `m5.large` (master), 2× `t3.medium` (`node-group-2`),
  and the untagged `t3.micro`.
- The hot update `0c625d8a-225b-3492-90d2-6f83580fa1ef` was still `InProgress`.
- Max 4 is not enough on its own. Once applied, the ASG would still try one
  more `m5.xlarge` (4 vCPU), which would make about 34 and fail. Either delete
  `node-group-2` first, which brings usage to about 26, or set max to 3 until
  capacity is available.

### 2026-10-26 (01:20 +08, 17:20 UTC): group-3 removed, group-2 deleting

- `node-group-3` no longer appears in `list-nodegroups`.
- `node-group-2` (2× `t3.medium`) was removed by the operator and is now
  `DELETING`. `node-group-1` remains `ACTIVE` with desired 0.
- At check time, 12 instances were still running (about 30 vCPU). Once
  `node-group-2` finishes, usage should be about 26 vCPU.
- The live hot ASG still has min 3, max 6, desired 6. The last launch failure
  was at 17:11 UTC. No launches have been attempted since.
- The hot update `0c625d8a-225b-3492-90d2-6f83580fa1ef` is still `InProgress`.
- Next, once `node-group-2` is gone, apply the EKS root with the hot group's
  max at 4 so the live ASG matches the config. The surge node then fits, at
  about 30 vCPU against the 32 limit.

### 2026-10-26 (01:29 +08, 17:29 UTC): quota freed, update fails again on a new node

- `node-group-2` is gone. The vCPU count from `describe-instances` is now 26
  for 9 running instances, against the 32 limit.
- The live hot ASG is now min 3, max 3, desired 3, with three healthy
  instances on launch template v1. Its max is 3 in AWS, not 4 as in the file.
- Update `0c625d8a-225b-3492-90d2-6f83580fa1ef` is `Failed` with
  `NodeCreationFailure`, the same message as before.
- The surge node `i-0d543b7444589460f` (us-east-2a) launched at 17:21:43 UTC.
  Two more hot nodes launched at about 17:22 and 17:24 UTC, `i-0be361eb9ed89bfbb`
  and `i-0cca6c7db27fc93ae`. All three were shut down by EKS within about a
  minute, with reason `Client.UserInitiatedShutdown`, as part of the rollback.
- Console output shows the new node booting correctly. `nodeadm` completed,
  containerd and kubelet `v1.36.5` were configured for
  `emirates-demo-eks-3SEf`, and the node IP was assigned. The log ends before
  kubelet reports a status.
- Cluster events show the new node registered for a short time. Its system
  DaemonSet pods (`aws-node`, `kube-proxy`, `eks-pod-identity-agent`,
  `ebs-csi-node`) were scheduled to it. It was then shut down and removed as
  "does not exist in the cloud provider".
- The existing hot AMI (`ami-06e6e691d7d05d43a`) and launch template v1 are
  unchanged. The only difference in launch template v2 is tags.
- Root cause for this failure is not yet confirmed. The node reached kubelet
  registration and was then shut down before it became `Ready`. The kubelet and
  `aws-node` logs from that node are not in the console output, and it has
  been terminated.
- Options that avoid the rolling update entirely:
  - Keep launch template v1 by removing the cluster-autoscaler tag changes from
    the hot group's launch template in Terraform. The group then never starts
    the update.
  - Add `update_config { max_unavailable = 1 }` to the hot group, so EKS
    replaces a node without launching a surge node.

## Validation

```bash
aws autoscaling describe-scaling-activities --region us-east-2 \
  --auto-scaling-group-name <asg-name> --max-items 5
aws eks describe-nodegroup --name emirates-demo-eks-3SEf \
  --nodegroup-name elasticsearch-hot-82c763f4e024a3db3b001af101 \
  --query 'nodegroup.{status:status,health:health,lt:launchTemplate}' --region us-east-2
kubectl get nodes -o wide
```

Expected results:

- No new `VcpuLimitExceeded` activities after the fix.
- The `VersionUpdate` completes or is retried successfully.
- The hot group has the desired node count, all `Ready`.
