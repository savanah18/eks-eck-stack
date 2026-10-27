# Beats
1. Deploy some necessary beats
```
kubectl -n elastic-stack apply -f beats-config/metricbeat_hosts.yaml
kubectl -n elastic-stack apply -f beats-config/stack_monitoring.yaml
kubectl -n elastic-stack apply -f beats-config/filebeat_autodiscover.yaml
```

2. Verify Successful Installation
```

```