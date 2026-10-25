# Elasticsearch Scheduling and Zonal Storage

**Date:** 2026-10-25  
**Environment:** `us-east-2`, three EKS Availability Zones, ECK Stack medium

## Symptom

Elasticsearch pods remained pending with scheduler messages such as:

```text
0/9 nodes are available:
1 node(s) didn't match pod anti-affinity rules,
2 node(s) didn't satisfy existing pods anti-affinity rules,
6 node(s) didn't match Pod's node affinity/selector
```

The node labels were correct: three nodes were labeled for the `master` role
and three for the `hot` role. The first deployment also retained the old
cluster-wide anti-affinity rule on already-running pods:

```yaml
elasticsearch.k8s.elastic.co/cluster-name: elasticsearch
```

Updating the StatefulSet template did not update existing pods immediately.
Those existing pods continued to apply the broad anti-affinity rule while new
pods were being scheduled.

The values were changed to role-scoped hard topology spread constraints:

- Masters match `elasticsearch.k8s.elastic.co/node-master=true`.
- Hot nodes match `elasticsearch.k8s.elastic.co/node-data_hot=true`.
- Each role has a `DoNotSchedule` constraint for
  `topology.kubernetes.io/zone`.
- Each role has a `DoNotSchedule` constraint for `kubernetes.io/hostname`.

Existing pods must be rolled so that they receive the updated topology
constraints.

## Root cause

The remaining scheduling failure was caused by zonal EBS volume placement.
Although the `gp2` StorageClass used `WaitForFirstConsumer`, the initial
claims had already been provisioned in `us-east-2a`. Each EBS volume has
immutable zone affinity, so the scheduler could not place those pods in the
other AZs required by the topology constraints.

Deleting and recreating the demo claims provisioned the volumes in separate
zones:

- Master volumes: `us-east-2a`, `us-east-2b`, `us-east-2c`
- Hot volumes: `us-east-2a`, `us-east-2b`, `us-east-2c`

## Recovery

For a disposable demo cluster, delete only the Elasticsearch pods and data
claims, then allow ECK to recreate them:

```bash
kubectl -n elastic-stack delete pod \
  -l common.k8s.elastic.co/type=elasticsearch \
  --wait=true

kubectl -n elastic-stack delete pvc \
  elasticsearch-data-elasticsearch-es-masters-0 \
  elasticsearch-data-elasticsearch-es-masters-1 \
  elasticsearch-data-elasticsearch-es-masters-2 \
  elasticsearch-data-elasticsearch-es-hot-0 \
  elasticsearch-data-elasticsearch-es-hot-1 \
  elasticsearch-data-elasticsearch-es-hot-2 \
  --wait=true
```

Verify placement and readiness:

```bash
kubectl -n elastic-stack wait \
  --for=condition=Ready \
  pod -l common.k8s.elastic.co/type=elasticsearch \
  --timeout=300s

kubectl get nodes \
  -L node-group,elasticsearch-role,topology.kubernetes.io/zone

kubectl -n elastic-stack get pods \
  -l common.k8s.elastic.co/type=elasticsearch \
  -o wide
```

This procedure is data-destructive. Do not delete Elasticsearch PVCs in an
environment that contains required data; restore the indices from a snapshot
or use a storage migration procedure instead.

## Result and remaining action

All six Elasticsearch pods became Ready and were distributed across the
three AZs. Because the demo PVCs were intentionally deleted, the old shard
copies were lost and Elasticsearch reported:

```text
health: red
unassigned_primary_shards: 54
can_allocate: no_valid_shard_copy
```

This is expected after deleting all data volumes. Recreate the demo cluster
or Elasticsearch resource to initialize a new cluster. If the data must be
preserved, restore from a snapshot instead. Kibana and Metricbeat may remain
running, but full monitoring functionality depends on Elasticsearch
returning to a healthy state.
