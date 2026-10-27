# ECK Zone-Awareness Update Blocked by Memory Resource Mismatch

**Date:** 2026-10-27  
**Environment:** `us-east-2`, EKS, ECK Stack medium  
**Status:** Open

## Symptom

An Elasticsearch zone-awareness configuration was being introduced while the
ECK-managed cluster was already reconciling a node update. The Elasticsearch
resource remained in `ApplyingChanges` with only five of six nodes available:

```yaml
status:
  availableNodes: 5
  phase: ApplyingChanges
```

The relevant ECK condition reported:

```text
Cannot get compute and storage resources from Elasticsearch resource
generation 4: cannot compute resources for NodeSet "hot":
memory request and limit do not have the same value
```

The cluster health was still `green`, but reconciliation was incomplete:

```text
Nodes upgrade: some nodes are not back in the cluster yet
```

## Resource configuration

The `hot` NodeSet had inconsistent memory resources:

```yaml
resources:
  limits:
    cpu: 4
    memory: 8Gi
  requests:
    cpu: "1"
    memory: 1Gi
```

The memory request and limit must match for ECK to calculate the NodeSet's
compute resources during resource-aware management. The zone-awareness setting
was not the direct cause of this error; the invalid memory pairing blocked ECK
from completing reconciliation.

The `masters` NodeSet also had different CPU requests and limits:

```yaml
resources:
  limits:
    cpu: 2
    memory: 1Gi
  requests:
    cpu: "0.5"
    memory: 1Gi
```

This is relevant if Kubernetes `Guaranteed` QoS is required, but the immediate
ECK error concerns the `hot` NodeSet's memory request/limit mismatch.

## Evidence

The Elasticsearch resource was configured with:

```yaml
spec:
  version: 9.5.0
  nodeSets:
  - name: hot
    count: 3
    zoneAwareness: {}
```

The status conditions showed:

- `RunningDesiredVersion=True`: all nodes were on Elasticsearch `9.5.0`.
- `ElasticsearchIsReachable=True`: the internal HTTP service had endpoints.
- `ResourcesAwareManagement=False`: ECK could not compute resources for `hot`.
- `ReconciliationComplete=False`: some nodes were not back in the cluster.
- `health: green`, with `phase: ApplyingChanges`.

These conditions indicate that the cluster was reachable and healthy at the
time of inspection, but the requested orchestration change had not finished.

## Root cause

The `hot` NodeSet declared an `8Gi` memory limit but only a `1Gi` memory
request. ECK's resource-aware management requires the memory request and limit
to have the same value for the NodeSet. Because the values differed, ECK could
not calculate the resource change required to manage the node update.

Zone awareness was being configured at the same time, but it was not the
reported validation failure. The resource mismatch prevented ECK from
progressing reliably through the reconciliation.

## Remediation

Update the Helm values owned by the ECK Stack release so the hot NodeSet uses
matching memory values:

```yaml
- name: hot
  resources:
    limits:
      memory: 8Gi
      cpu: 4
    requests:
      memory: 8Gi
      cpu: "1"
```

Apply the change through the Terraform-managed ECK release rather than editing
the generated Elasticsearch custom resource or StatefulSet directly:

```bash
cd iac/terraform/eck
terraform plan -var='flavor=medium'
terraform apply -var='flavor=medium'
```

Use the repository's normal Terraform variables and backend settings when
running these commands.

## Validation

Check that ECK has observed the new generation and completed reconciliation:

```bash
kubectl -n elastic-stack get elasticsearch elasticsearch \
  -o jsonpath='phase={.status.phase}{"\n"}health={.status.health}{"\n"}'

kubectl -n elastic-stack get elasticsearch elasticsearch \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}: {.message}{"\n"}{end}'

kubectl -n elastic-stack get pods \
  -l common.k8s.elastic.co/type=elasticsearch -o wide
```

Expected results:

- `ResourcesAwareManagement=True`.
- `ReconciliationComplete=True`.
- All six Elasticsearch pods are `Ready`.
- `availableNodes` is `6`.
- The cluster returns to `green` after any expected shard relocation.
- No new `Insufficient memory` or repeated reconciliation errors appear.

Confirm the effective pod resources:

```bash
kubectl -n elastic-stack get pod <pod-name> -o json |
  jq '.spec.containers[] |
    {name, requests: .resources.requests, limits: .resources.limits}'
```

## Guaranteed QoS note

Matching memory requests and limits fixes the ECK error, but it does not by
itself make the pod Kubernetes `Guaranteed` QoS. For `Guaranteed`, every
container must have CPU and memory requests equal to their corresponding
limits. The hot NodeSet would additionally require:

```yaml
resources:
  requests:
    memory: 8Gi
    cpu: 4
  limits:
    memory: 8Gi
    cpu: 4
```

Only make the CPU change after confirming that the node group has sufficient
allocatable CPU and memory for the new requests and for rolling replacement.

## Precautions

- Do not delete Elasticsearch PVCs to resolve this reconciliation error.
- Do not edit the generated StatefulSet directly; ECK will overwrite it.
- Confirm node allocatable memory before increasing the request to `8Gi`.
- Monitor pod replacement, PVC attachment, shard allocation, and cluster health.
- If the update remains stuck, inspect ECK operator logs and Elasticsearch
  events before making further changes:

```bash
kubectl -n elastic-system logs deploy/elastic-operator --since=30m
kubectl -n elastic-stack get events --sort-by=.lastTimestamp
```

