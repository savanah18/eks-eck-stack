# Elasticsearch PVC and Zone Affinity Scheduling

**Date:** 2026-10-24  
**Environment:** `us-east-2`, EKS `1.37`, `emirates-demo-eks-cluster`

## Symptom

One Elasticsearch StatefulSet pod remained `Pending` after the node group was
scaled to three nodes.

The scheduler reported:

```text
node didn't match PersistentVolume's node affinity
node didn't match pod anti-affinity rules
```

## Root cause

The Elasticsearch PVC had already been bound to an EBS volume in
`us-east-2a`. Another Elasticsearch pod was already running in that zone.
Required zone anti-affinity prevented the pending pod from using the same
zone, while the PVC prevented it from using another zone.

The issue was caused by enabling zone anti-affinity before all three eligible
AZ nodes were available and before volume placement was stable. It was not
caused by missing anti-affinity; without anti-affinity, pods could have been
co-located in one AZ, but the deployment would have been less resilient.

## Remediation

The demo Elasticsearch data was disposable, so all Elasticsearch PVCs and
their dynamically provisioned PVs were deleted. The StatefulSet then
recreated the volumes and pods after three eligible nodes were available.

The cluster recovered with all Elasticsearch pods recreated successfully.

## Prevention

- Create all three AZ node-group capacity before deploying Elasticsearch.
- Keep `volumeBindingMode: WaitForFirstConsumer`.
- Use zone-aware pod anti-affinity or topology spread constraints.
- Use a dedicated Elasticsearch StorageClass with an intentional reclaim
  policy.
- Do not delete PVCs in a data-bearing cluster; restore from snapshots or
  migrate data instead.
