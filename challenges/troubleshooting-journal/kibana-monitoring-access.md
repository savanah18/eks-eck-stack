# Kibana Stack Monitoring Access

**Date:** 2026-10-24  
**Environment:** `us-east-2`, EKS `1.37`, `emirates-demo-eks-cluster`

## Symptom

Kibana Stack Monitoring reported:

```text
You are not authorized to access Monitoring.
```

The authenticated user was verified as `elastic` with the `superuser` role,
so the issue was not Elasticsearch authentication.

## Root cause

Kibana had Cross-Cluster Search enabled:

```text
monitoring.ui.ccs.enabled: true
```

This single-cluster deployment did not require CCS or a dedicated monitoring
cluster.

## Resolution

Set the Kibana configuration to:

```yaml
monitoring.ui.ccs.enabled: false
```

### Option 1: Helm values (recommended)

Add the setting to the Helm values:

```yaml
eck-kibana:
  config:
    monitoring.ui.ccs.enabled: false
```

Apply it:

```bash
helm upgrade eck-stack-small elastic/eck-stack \
  -f ../../iac/terraform/eks/values/eck-stack-values-eks-demo-small.yaml \
  -n elastic-stack \
  --timeout 10m \
  --wait
```

This keeps Helm as the persistent source of truth.

### Option 2: Update the Kibana custom resource

For a direct ECK custom-resource update:

```bash
kubectl patch kibana eck-stack-small-eck-kibana \
  -n elastic-stack \
  --type merge \
  -p '{"spec":{"config":{"monitoring.ui.ccs.enabled":false}}}'
```

This is suitable for diagnosis or an immediate fix, but a later Helm upgrade
may overwrite the change or report a field-ownership conflict. The setting
should ultimately be added to the Helm values.

## Validation

The solution was verified by logging into Kibana with the `elastic` user and
accessing Stack Monitoring successfully.
