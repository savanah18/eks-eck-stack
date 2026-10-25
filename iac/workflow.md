# EKS Setup
## Install (using Terraform)
1. Format and Initialize
  ```
  cd iac/terraform/eks
  terraform fmt -recursive
  terraform init
  ```
3. Validate, Plan and Apply
   ```
   terraform validate
   terraform plan
   terraform apply
   ```
   This root provisions only the AWS and EKS infrastructure.

4. Destroy (Optional)
   ```
   terraform destroy
   ```

## Verification
1. Configure kubeconfig
    ```
    aws eks update-kubeconfig \
    --region us-east-2 \
    --name "$(terraform output -raw cluster_name)"
    ```
2. Quick-check cluster info
    ```
    kubectl cluster-info 
    ```

Ensure the AWS CLI is installed and the active credentials can access the EKS
cluster before running the separate autoscaler, ECK, and NetworkPolicy roots.

# Public Kibana Ingress
Only when the EKS root has `mode=production`: the ECK root keeps Kibana's Service
as `ClusterIP`, the EKS root installs the EKS-managed `external-dns` add-on, and
the ingress root installs the AWS Load Balancer Controller and creates an HTTPS
ALB Ingress in `elastic-stack`. With `mode=demo` (the default) the ECK root exposes
Kibana through a `LoadBalancer` Service instead, and neither the ingress root nor
ExternalDNS is created.

Prerequisites:

- A domain you own, whose DNS the EKS root's Route 53 zone will serve.
- An ACM certificate in the cluster region covering the Kibana hostname.
- The EKS `eks-pod-identity-agent` add-on, enabled by the EKS root.

Apply the EKS root in production mode first. This creates the Route 53 zone for
`domain_name` and the EKS-managed ExternalDNS add-on:

```bash
cd iac/terraform/eks
terraform apply -var="mode=production" -var="domain_name=example.com"
terraform output route53_name_servers
```

Set those name servers as the domain's NS records at your registrar before the
ACM certificate validation or any DNS record will resolve. The zone has
`prevent_destroy` set, so remove that lifecycle entry deliberately before destroying it.

Apply the ingress after the ECK stack:

```bash
cd iac/terraform/ingress
terraform init
terraform validate
terraform apply \
  -var="cluster_name=$(cd ../eks && terraform output -raw cluster_name)" \
  -var="kibana_hostname=kibana.example.com" \
  -var="acm_certificate_arn=<acm-certificate-arn>"
```

The ALB is internet-facing but only exposes HTTPS to clients; HTTP is
redirected to HTTPS. The backend remains HTTPS to ECK's private Kibana
Service. The EKS-managed ExternalDNS add-on is limited to the zones listed in
`external_dns_hosted_zone_arns` by its IAM role and uses TXT ownership records.

# Cluster Autoscaler Setup
## Configure autoscaling for Elasticsearch hot/data nodes

The EKS root defines the hot node group with scaling bounds:

```hcl
min_size     = 3
desired_size = 3
max_size     = 6
```

Only the `elasticsearch-hot` managed node group has the Cluster Autoscaler
discovery tags:

```hcl
"k8s.io/cluster-autoscaler/enabled"               = "true"
"k8s.io/cluster-autoscaler/<cluster-name>"        = "owned"
```

The `system` and `elasticsearch-master` node groups are not tagged for
autoscaling. Their capacity is therefore not managed by this autoscaler
configuration.

The autoscaler root installs Cluster Autoscaler and configures its EKS Pod
Identity role:

```bash
cd iac/terraform/autoscaler
terraform init
terraform validate
terraform apply \
  -var="cluster_name=$(cd ../eks && terraform output -raw cluster_name)" \
  -var="region=us-east-2"
```

Cluster Autoscaler scales the tagged hot node group when an eligible
Elasticsearch pod remains unschedulable because of resource requests or
topology constraints. `max_size` only sets the upper limit; the autoscaler is
the controller that changes the desired node count.

Verify the autoscaler and the selected node group:

```bash
kubectl -n kube-system get deployment cluster-autoscaler
kubectl -n kube-system logs deployment/cluster-autoscaler --tail=100
kubectl get nodes \
  -l node-group=eck-stack,elasticsearch-role=hot \
  -L topology.kubernetes.io/zone
```

Verify the AWS Auto Scaling Group discovery tags:

```bash
export CLUSTER_NAME="$(
  cd iac/terraform/eks &&
  terraform output -raw cluster_name
)"

aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Tags:Tags}'
```

The hot node group must retain these labels so the scaled nodes satisfy the
ECK node affinity rules:

```hcl
"node-group"         = "eck-stack"
"workload"           = "elasticsearch"
"elasticsearch-role" = "hot"
```

# ECK Setup
## Install ECK Operator + Instantiate (Elasticsearch, Kibana, Beats)
After the cluster is reachable, deploy the ECK operator and stack from the
separate Terraform root:
  ```bash
  cd iac/terraform/eck
  terraform init
  terraform apply \
    -var="cluster_name=$(cd ../eks && terraform output -raw cluster_name)" \
    -var="flavor=medium"
  ```

## Verify Successful Installation
  ```
  kubectl -n elastic-system get sts,pods,pvc
  kubectl -n elastic-system get elasticsearch,kibana,beats
  kubectl -n elastic-stack get pods \
  -l common.k8s.elastic.co/type=elasticsearch \
  -o custom-columns='NAME:.metadata.name,MASTER:.metadata.labels.elasticsearch\.k8s\.elastic\.co/node-master,HOT:.metadata.labels.elasticsearch\.k8s\.elastic\.co/node-data_hot,ZONE:.metadata.labels.topology\.kubernetes\.io/zone,STATUS:.status.phase'
  ```

## Configure secure network policies
Apply the NetworkPolicies only after ECK is healthy:

```bash
cd ../netpol
terraform init
terraform apply \
  -var="cluster_name=$(cd ../eks && terraform output -raw cluster_name)"
```

Verify the deployment:

```bash
kubectl -n elastic-system get pods
kubectl -n elastic-stack get elasticsearch,kibana,beats,pods
kubectl -n elastic-stack get networkpolicy
```
