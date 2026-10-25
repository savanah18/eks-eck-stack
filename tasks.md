# SRE Take-Home Exercise: Elastic Cluster on Kubernetes

## Time Expectation

Candidates have **one week** (calendar time) to complete and submit this exercise. Prioritize a working, well-reasoned core solution over exhaustive polish. Where you make a time tradeoff, note it in the README under "Challenges, assumptions, and limitations."

## Problem Statement

Design and deploy an Elastic cluster on Kubernetes. The solution should demonstrate a practical understanding of running a stateful application on Kubernetes, including storage, scalability, reliability, and monitoring.

The candidate can use Elastic Cloud on Kubernetes (ECK) or another suitable approach.

## Prerequisites

The candidate has access to a public cloud provider (Azure/AWS) and the following utilities are available: `kubectl`, `helm`, `terraform`.

Elastic **Basic (free) license tier is sufficient** for this exercise — no trial or Enterprise features are required or expected.

## Deliverables

### Kubernetes Cluster
- Kubernetes cluster is provisioned on AKS/EKS.
- Cluster nodes span **multiple availability zones** (minimum 3 AZs where the region supports it).
- Appropriate node pools are configured for Elasticsearch.
- Kubernetes resource requests and limits are defined for Elasticsearch NodeSets and Pods.
- Pod scheduling considerations such as pod anti-affinity and node topology spread are implemented, **explicitly accounting for AZ** (not just node/hostname) — e.g. using `topology.kubernetes.io/zone` — so that data and master-eligible nodes are distributed across zones.

### Storage and Resources
- Persistent storage and storage class is configured for Elasticsearch data.
- Persistent Volume and PVC sizing.

### Security and Networking
- Kubernetes NetworkPolicy is configured where appropriate for Elastic Transport to function.
- Secrets are handled using Kubernetes Secrets or an appropriate mechanism such as Vault.
- Ingress or LoadBalancer configured if external access is required.
- Appropriate firewall rules/policies are set for Ingress and Egress.

### Infrastructure as Code Repository
Use Terraform to provision the Kubernetes infrastructure and deploy/manage the Elastic components where practical.

### Automation
Provide a few scripts for common operations, for example, but not limited to:
- Scaling Elasticsearch nodes.
- Creating a new Elasticsearch index.

### Monitoring
Set up basic monitoring for Elasticsearch and Kubernetes, covering:
- ES cluster health.
- CPU, memory, JVM usage.
- Disk metrics (IOPS, R/W rate).
- Index/search activity.
- Unassigned shards.
- K8s pod status/restarts/OOM/resource exhaustion.
- Persistent volume usage.
- Thread pool stats.

The candidate may use Elastic/Kibana, Prometheus/Grafana, Azure Monitor, CloudWatch, or another suitable monitoring solution.

### Documentation

The README should include:
- Infra overview.
- Configuration and sizing decisions.
- Scaling / AKS (or EKS) upgrade procedure.
- Troubleshooting steps for consumers.
- Monitoring setup.
- Challenges, assumptions, and limitations.

## Success Criteria

**Elasticsearch Functionality**
- Elasticsearch cluster is running successfully.
- Data can be indexed and queried.
- Kibana can connect to and interact with Elasticsearch.
- Cluster, node health, and scaling can be demonstrated.
- Nodes are distributed across multiple availability zones as designed.

## Review

After submission, we'll schedule a meeting where you walk us through your solution and demo the running cluster. Please have the environment up and accessible for that call, and be prepared to demonstrate:
- Cluster health, indexing, and querying data.
- Scaling Elasticsearch nodes up.
- An availability zone going down (e.g. cordon/draien the nodes in one zone) and the cluster's behavior/recovery.

