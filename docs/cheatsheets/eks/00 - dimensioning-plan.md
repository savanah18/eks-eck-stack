## Elasticsearch Deployment Options

Both options use ECK to manage Elasticsearch and Kibana on the three-AZ EKS cluster. The ECK operator and Kibana run on the system node group.

### Option 1: Combined Elasticsearch nodes

A smaller, cost-conscious deployment with three Elasticsearch nodes. Each node performs master, data, and ingest functions.

```text
System nodes:          3 x t3.medium or larger
Elasticsearch nodes:   3 x m5.large or equivalent
Availability Zones:    1 node per AZ
```

Example:

```yaml
nodeSets:
  - name: default
    count: 3
    config:
      node.roles: ["master", "data", "ingest"]
```

**Use when:**

- The workload is small.
- Cost and simplicity are priorities.
- The deployment is intended mainly for demonstration.

**Limitations:**

- Cluster coordination, storage, indexing, and searching share the same nodes.
- Less isolation and scalability than dedicated roles.
- A single node loss reduces both master and data capacity.
- Hot/warm/cold data tiers are not demonstrated.

---

### Option 2: Dedicated master and data nodes

A production-style deployment with separate master and data responsibilities.

```text
System nodes:          3 x t3.medium or larger
Master nodes:          3 x m5.large or equivalent
Hot data nodes:        3 x m5.xlarge or equivalent
Warm data nodes:       Optional 3-node tier
Availability Zones:    All node groups spread across 3 AZs
```

Example:

```yaml
nodeSets:
  - name: masters
    count: 3
    config:
      node.roles: ["master"]

  - name: hot
    count: 3
    config:
      node.roles: ["data_hot", "data_content", "ingest"]

  - name: warm
    count: 3
    config:
      node.roles: ["data_warm"]
```

**Use when:**

- High availability and role separation are required.
- The deployment must demonstrate scaling and AZ failure recovery.
- Different storage and performance profiles are needed for data tiers.

**Requirements:**

- Zone-aware scheduling using `topology.kubernetes.io/zone`.
- Pod anti-affinity and topology spread constraints.
- Dedicated EBS-backed PVCs using the EBS CSI driver.
- Explicit CPU and memory requests and limits.
- Elasticsearch nodes isolated with labels and taints.
- Replica shards configured to tolerate node or AZ loss.

---

### Common components

Both options include:

- EKS spanning `us-east-2a`, `us-east-2b`, and `us-east-2c`
- ECK operator on system nodes
- ECK-managed Kibana
- EBS CSI-backed `gp3` storage
- Kubernetes Secrets and ECK-managed TLS
- NetworkPolicies for Elasticsearch transport and HTTP traffic
- Monitoring for Elasticsearch, Kubernetes, and PVCs
- Terraform for infrastructure and Helm/ECK deployment management

### Recommendation

Use **Option 1** for a minimal, low-cost demonstration.

Use **Option 2** for the submitted solution because it better satisfies the requirements for:

- Dedicated node pools
- Multi-AZ resilience
- Elasticsearch scaling
- AZ failure testing
- Hot/warm data separation
- Production-oriented Kubernetes design

The current cluster, with two `t3.medium` data nodes and zero system/manager nodes, must be resized before either option can be deployed reliably.