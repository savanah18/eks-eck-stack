# ECK Helm Field Ownership Conflict

**Date:** 2026-10-24  
**Environment:** `us-east-2`, EKS `1.37`, `emirates-demo-eks-cluster`

## Symptom

Updating the ECK Stack Helm release failed while applying the Elasticsearch
custom resource:

```text
UPGRADE FAILED: conflict occurred while applying object
elastic-stack/elasticsearch elasticsearch.k8s.elastic.co/v1, Kind=Elasticsearch:
Apply failed with 1 conflict: conflict with "elastic-operator" using
elasticsearch.k8s.elastic.co/v1: .spec.nodeSets
```

## Scope

The `Elasticsearch` custom resource already existed in the `elastic-stack`
namespace. The Helm release attempted to update
`.spec.nodeSets`, which was already recorded in Kubernetes server-side
managed fields as owned by `elastic-operator`.

This was a Kubernetes field-ownership conflict. It was not caused by
insufficient CPU, memory, storage, or an incompatible ECK chart.

## Investigation

Check the existing resource and its field managers:

```bash
kubectl get elasticsearch elasticsearch \
  -n elastic-stack \
  -o yaml

kubectl get elasticsearch elasticsearch \
  -n elastic-stack \
  -o json |
  jq '.metadata.managedFields[] |
    {manager, operation, fieldsType, time}'
```

Check Helm releases:

```bash
helm list -n elastic-stack
helm status eck-stack-small -n elastic-stack
```

## Evidence

The conflicting field was:

```text
.spec.nodeSets
```

The existing owner reported by the API server was:

```text
elastic-operator
```

The attempted Helm release was also applying the same field.

## Root cause

The same ECK `Elasticsearch` custom resource was being managed by more than
one server-side apply manager. The existing resource and the Helm release did
not have a single authoritative owner for `.spec.nodeSets`.

## Remediation

If the Helm release is intended to become the authoritative configuration
owner, use Helm's conflict override:

```bash
helm upgrade --install eck-stack-small elastic/eck-stack \
  -f ../../iac/terraform/eks/values/eck-stack-values-eks-demo-small.yaml \
  -n elastic-stack \
  --create-namespace \
  --force-conflicts \
  --timeout 10m \
  --wait
```

Use `--force-conflicts` only after confirming that the values file contains
the desired complete Elasticsearch configuration.

If the cluster can be safely recreated, an alternative is to delete and
recreate the custom resource. Confirm PVC retention and data recovery first:

```bash
kubectl get pvc -n elastic-stack

kubectl get elasticsearch elasticsearch \
  -n elastic-stack \
  -o yaml |
  grep -A4 persistentVolumeClaimRetentionPolicy
```

Do not delete the Elasticsearch resource without confirming that required data
is retained and recoverable.

## Prevention

Use one configuration owner for the `Elasticsearch` custom resource:

- ECK Stack Helm release, or
- standalone ECK component Helm release, or
- raw Kubernetes manifest, or
- Terraform-managed manifest.

Do not manage the same custom resource with multiple Helm releases or with a
mixture of Helm and manually applied manifests.

The ECK operator should reconcile the resource and generated StatefulSets,
Services, PVCs, and Secrets. The selected Helm release should own the
Elasticsearch and Kibana custom-resource configuration.

## Validation

- [ ] Confirm only the intended Helm release manages the Elasticsearch resource.
- [ ] Confirm the Helm upgrade completes successfully.
- [ ] Confirm the Elasticsearch resource reports a ready status.
- [ ] Confirm StatefulSet and pod readiness.
- [ ] Confirm existing PVCs remain attached and data is available.
- [ ] Confirm no repeated field-conflict events appear.
