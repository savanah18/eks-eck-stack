# Elastic Cluster on Kubernetes
---

## Introduction
### Problem Statement
This project involves designing and deploying an **Elastic Cluster on Kubernetes** that demonstrates practical understanding of running a stateful applications on top of an orchestration solution with **storage**, **scalability**, **reliability** and **observability** in consideration. 

### Challenges, Assumptions and Limitations

This project is limited to the following


## Infrastructure Overview
This project is built on top of Amazon Web Services (AWS) as public cloud infrastructure provisioner - specifically **AWS Elastic Kubernetes** (AWS EKS). The target stateful applications that is the subject of deployment is an **Elastic Cluster** - a highly-available / scalable distributed search and analytics engine. 

The EKS Cluster is deployed over a **Virtual Private Cloud** with all the required and necessary networking requirements configured. Compute nodes provisioned on **multiple availability zones** across selected a selected region. Different sets **EKS managed node groups** is also provisioned representing different kind of compute requirements - with some node groups labeled for *autoscaling capabilities*. Different EKS cluster add-ons (Core DNS, CSI Driver, CNI, etc) are also added.

The Elastic Cluster is configured and deployed over an **Elastic Cloud on Kubernetes Operator**(ECK Operator) through *operator-based deployment pattern* with custom resources wrapped in an existing public helm chart. For this project, different **elasticsearch nodesets**(master, data, etc) with *dedicated affinity and spread contraints* for optimal availability. A dedicated **kibana deployment** is also added for **visualization** and more importantly for this project - *observability* and *monitoring*.  Additional **beats**  deployments are also deployed for *host/eck stack metrics collection*. 

An **alb type ingress** is provisioned for kibana for internet-facing exposure with *necessary security protocols* setup. Multiple **kubernetes network policies** are provisioned to control ingress and egress traffic - as no network policies is configured by default. 

## Design 
The following details all significant design decisions and configuration. 

### Prerequisite
- An existing public account and IAM user credentials
- Access to tools like `helm`, `aws cli`, `helm`, and `terraform`

### AWS EKS Configuration and Dimensioning
**VPC Configuration**
Prior to to AWS EKS setup, a dedicated VPC is setup. The VPC is created over *3 AZ* with dedicated *public* and *private subnets*, *igw and nat gateways*, dedicated *route tables*, *security groups and NACLs*. 

**EKS Setup**
For the EKS setup, a [terraform eks public module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest) is used. Default values does not necessarily satisfy our problem requirements - and additional configurations were needed. 

- Kubernetes Version: `1.36`, 
- Add-ons: `CoreDNS` , `VPC CNI`, `AWS EBS CSI Driver`, `Kube Proxy`, `Pod Identity Agent`, `Eternal DNS` (Optional)
- **3 Managed EKS Node Group**
  1. **System** - for all utility services, operators, etc
  2. **Master** - node group dedicated for Elasticsearch nodes with master roles
  3. **Hot** - node group dedicated for Elasticsearch nodes with data roles
- Each node groups are also distinctively labeled according to nodegroup, roles, workload, etc. Labels are very significant in how the ECK cluster behaves. 

For this demo project: 
- Each node groups used the vpc's private subnets (for security)
- Only the `hot` nodegroup are configured with `m5.large` instance types, wit the rest being `t3.medium`
- Only the `hot` nodegroup are configured with autoscaling enabled `active autoscaling` and with higher `max_size=4` for potential node-level scaling.

### Elastic Cluster
As stated, the elastic-stack is deployed using [ECK Operator](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/install-using-helm-chart). Different custom resources wrapped in a publicly available helm chart are configured and deployed (elasticsearch, kibana, beats). 
Please see eck configuration, dimensioning and other settings below:

**Elasticsearch**
- `2 nodesets` (masters, hot)
- Master Nodesets:
  - `3 replicas`: minium HA config with reliable quorum
  - requests: `0.5 cpu`, `2Gi memory` (slightly toned down for this project)
- Hot Nodesets (Data):
  - `3 replicas, up to 4 (scale up)`: minium HA config with reliable quorum
  - requests: `1 cpu`, `2Gi memory` (slightly toned down for this project)

- General Configurations
  - `node affinity` configured according to nodegroup role
  - pod anti-affinity is not considered due to unschedulable pods when scaling up due to strict pod anti-affinity or potential data corruption for soft pod anti-affinity when some available zone shutdowns (and affected pod is schedule in unaffected zones anyway)
  - `Topology constraints` is configured instead with max skew=1
  - `GP2` storage class is used(10Gi for master, 50Gi for hot - toned down for this project) which is compatible with the existing `AWS EBS CSI addon`
  - Service LoadBalancer can be temporarily enabled for development purposes. But an ingress and proper alb is configured for this. 
  - Make sure pod disruption budged is properly configure to properly simulate AZ shutdown. 
- Important Note
  - For `ResourcesAwareManagement condition` to proceed during Elasticsearch resource updates, it is required to let memory request and limits equal. 

**Kibana**
- Stack Monitoring enabled
- Service LoadBalancer can be temporarily enabled for development purposes. But an ingress and proper alb is configured for this.  
- Node Affinity and Topology constraints configured (Optional, kibana is stateless)

**Beats**
- Several metric beats are deployed as daemonsets with metrics collected from the system, kubernetes, elasticsearch, and kibana. 

> Please see configuration for eck stack in [eck-stack-values-eks-demo-medium](iac/terraform/eck/values/eck-stack-values-eks-demo-medium.yaml)


### Network Policy
By default, no network policy is configured by default for all ther services and thus service calls are mostly open. With this, a `default deny ingress/egress` policy is configured. Seperate ingress/egress network policy are configured for relevant services: Elasticsearch, Kibana and Metric Beats. 


## Scaling / Upgrade Procedures
### Upgrade Procedures
#### Scaling Elasticsearch

Update the Elasticsearch NodeSet `count` in the ECK values file, then apply the change through Terraform. Verify that the new pods become ready, are distributed across the expected availability zones, and that Elasticsearch reports a healthy cluster. Scaling may wait for node capacity, topology constraints, or EBS volume placement.

#### Upgrades

Review version compatibility before upgrading EKS, ECK,Elasticsearch, Kibana, or Beats. Apply upgrades through Terraform and verify node, pod, operator, Elasticsearch, Kibana, and Beat health after each step. During a node drain, Elasticsearch pods may remain Pending until suitable capacity is available because topology constraints prevent unbalanced placement.

##### EKS upgrade sequence

1. Review the target Kubernetes version and compatible EKS add-on versions.
2. Upgrade the EKS control plane through the EKS Terraform root.
3. Upgrade VPC CNI, CoreDNS, kube-proxy, EBS CSI, and Pod Identity add-ons.
4. Upgrade managed node groups and verify that replacement nodes become
   `Ready`.
5. Drain nodes one at a time, observing Elasticsearch pod placement, PVC
   attachment, shard relocation, and cluster health.
6. Verify ECK, Elasticsearch, Kibana, Metricbeat, and Kubernetes system pods
   before continuing.

## Infrastructure as Code

Terraform is organized into separate roots so infrastructure layers can be applied independently:

- `iac/terraform/eks`: VPC-backed EKS cluster, managed node groups, and EKS add-ons.
- `iac/terraform/eck`: ECK operator and the Elasticsearch, Kibana, and Metricbeat resources. The `flavor` variable selects the stack values file.
- `iac/terraform/ingress`: AWS Load Balancer Controller, ExternalDNS, ACM-backed Kibana ingress, and DNS integration for production access.
- `iac/terraform/netpol`: Kubernetes network policies for the Elastic workloads.
- `iac/terraform/autoscaler`: Cluster Autoscaler resources and IAM configuration.

Apply the EKS root first, then the ECK root. Apply ingress, network policy, and autoscaling only when their prerequisites and deployment mode require them. Each root should be initialized, validated, planned, and applied from its own directory. Terraform state files are local in this project, so state must be preserved and protected when operating the environment.

## Automation

The repository includes scripts for the main demonstration workflows:

- [`demo_bookings.sh`](scripts/demo_bookings.sh) creates the flight-bookings index and alias, indexes sample documents, and runs queries against Elasticsearch.
- [`az_outage.sh`](scripts/az_outage.sh) supports the availability-zone outage exercise by cordoning and draining selected nodes, then checking Elasticsearch health, shard placement, and recovery.

These scripts use the existing cluster credentials and endpoint configuration. 

## Monitoring Setup

This project uses Kibana Stack Monitoring rather than a separate Prometheus/Grafana observability stack. Metricbeat runs as a DaemonSet and collects system, Kubernetes, Elasticsearch, and Kibana metrics. The Elasticsearch and Kibana X-Pack modules send monitoring data to the cluster's `.monitoring-*` data streams.

Stack Monitoring provides visibility into Elasticsearch cluster and node health, CPU and memory usage, JVM and disk statistics, index and search activity, unassigned shards, and thread-pool activity. Metricbeat's Kubernetes and system modules also provide pod/node resource and status metrics, including restart and capacity signals. Persistent volume capacity and filesystem usage are visible through the collected node and filesystem metrics.

The monitoring views are available from Kibana's Stack Monitoring application. The following screenshots show the monitoring overview, node metrics, and index activity:
- [Stack Monitoring overview](docs/kibana-stack-monitoring.png)
- [Node monitoring](docs/kibana-stack-monitoring-nodes.png)
- [Index monitoring](docs/kibana-stack-monitoring-indices.png)

Monitoring data may take a short time to appear after Metricbeat starts or
after a deployment change.

## Challenges, Assumptions and Limitations

### Challenges

- **EKS add-on readiness:** An add-on can report as installed while its pods
  are unhealthy. The VPC CNI and EBS CSI components require the correct IAM
  permissions and Pod Identity associations before nodes and persistent
  volumes can be considered ready.
- **Terraform and Kubernetes readiness:** ECK is applied from a separate
  Terraform root after EKS is available. This avoids applying Helm resources
  while the Kubernetes API is still becoming ready. Helm OpenAPI validation
  is disabled to avoid a control-plane timeout, while readiness waits remain
  enabled.
- **ECK resource ownership:** Elasticsearch and Kibana custom resources must
  have one configuration owner. The ECK Stack Helm release is the source of
  truth; manually applying competing manifests can cause server-side field
  ownership conflicts.
- **Zonal scheduling and storage:** Elasticsearch uses role-specific node
  affinity and hard topology spread constraints across availability zones and
  hostnames. EBS volumes are zone-bound, so PVC placement and available node
  capacity can leave pods Pending during scale-up or node drains.
- **Ingress dependencies:** Production HTTPS access depends on an ACM
  certificate and a DNS domain that is controlled and delegated. A demo can
  use an AWS Load Balancer hostname, but HTTP or a self-signed certificate is
  not suitable for production.

### Assumptions

- The deployment targets AWS EKS in a region with three Availability Zones.
- Terraform roots are applied in dependency order, with EKS available before ECK and optional ingress, network policy, or autoscaler layers.
- Elasticsearch data is stored on EBS-backed PVCs through the AWS EBS CSI driver.
- The ECK Stack Helm release owns the Elastic custom resources, and Metricbeat is the selected Stack Monitoring collection method.
- The Basic Elastic license is sufficient, and the demo uses Kubernetes Secrets for generated credentials.
- Demo data can be recreated or restored from snapshots; production data must not be deleted with PVCs.

### Limitations

This implementation was completed within a limited timeframe using relevant public documentation, examples, and extensive testing and reconfiguration. The deployment is intentionally a medium-sized, demo-grade configuration rather than a fully hardened production design. Instance types, replica counts, storage sizes, and resource requests are constrained by budget. The project therefore demonstrates the architecture and operating procedures, but does not represent a final production sizing or capacity plan. 
Production use would require independent sizing, durable remote Terraform state, certificate and DNS ownership, backup and restore validation, security hardening, and a formal upgrade and disaster-recovery process.

## Troubleshooting Steps for Consumers

### Confirm deployment reachability

```bash
kubectl cluster-info
kubectl get nodes
kubectl -n elastic-stack get pods
```

All required nodes should be `Ready`, and the Elasticsearch, Kibana, and Metricbeat pods should be running.

### Check Elastic resource health

```bash
kubectl -n elastic-stack get elasticsearch,kibana,beats
kubectl -n elastic-stack get events --sort-by=.lastTimestamp
```

If a resource is not progressing, check the ECK operator:

```bash
kubectl -n elastic-system logs sts/elastic-operator --since=15m
```

### Check Elasticsearch health

From Kibana Dev Tools:

```http
GET _cluster/health
GET _cat/nodes?v
GET _cat/shards?v
```

Investigate `red` health, unassigned primary shards, or nodes missing from the
cluster.

### Check Kibana access

```bash
kubectl -n elastic-stack get svc,ingress kibana
kubectl -n elastic-stack get pods \
  -l kibana.k8s.elastic.co/name=kibana
kubectl -n elastic-stack describe ingress kibana
```

Production HTTPS access requires a valid ACM certificate and a delegated DNS
name. A demo LoadBalancer or self-signed certificate is not production-ready.

### Check monitoring data

Metricbeat monitoring data may take a short time to appear after startup or a
deployment change.

```bash
kubectl -n elastic-stack get beat,pods
kubectl -n elastic-stack logs \
  -l beat.k8s.elastic.co/name=metricbeat \
  --since=15m
```

In Kibana Dev Tools:

```http
GET _cat/indices/.monitoring-*?v
```

If monitoring data exists but the dashboard is empty, wait briefly, refresh
Kibana, and select a wider time range such as **Last 1 hour**.

### Check pending Elasticsearch pods

```bash
kubectl -n elastic-stack get pods -o wide
kubectl -n elastic-stack describe pod <pod-name>
kubectl get nodes \
  -L node-group,elasticsearch-role,topology.kubernetes.io/zone
```

Pods may remain `Pending` because of hard topology spread constraints,
unavailable node-group capacity, EBS volume zone affinity, PVC attachment or
provisioning, or a node drain. Do not delete Elasticsearch PVCs unless the
data is disposable or recoverable from snapshots.

### Check node and storage dependencies

```bash
kubectl -n kube-system get pods
kubectl -n kube-system get pods -l k8s-app=aws-node
kubectl -n kube-system get pods -l app=ebs-csi-controller
kubectl -n elastic-stack get pvc
```

If nodes are `NotReady`, inspect VPC CNI status and logs. If PVCs remain
pending, inspect the EBS CSI controller and StorageClass.

Detailed incident-specific procedures are documented in the
[troubleshooting journal](docs/challenges/troubleshooting-journal/).
