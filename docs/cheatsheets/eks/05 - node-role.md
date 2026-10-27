## Create the EKS managed node IAM role

This role is assumed by the EC2 instances in an EKS managed node group. It is
different from the EKS cluster role and from add-on Pod Identity roles.

Run this script before creating the managed node group:

```bash
chmod +x create-node-role.sh
./create-node-role.sh emirates-demo
```

The node role needs `AmazonEKSWorkerNodePolicy` and ECR pull permissions. The
VPC CNI policy is intentionally not attached here because this setup creates a
dedicated Pod Identity role for the VPC CNI.

If you are not configuring the VPC CNI with its dedicated Pod Identity role,
attach this additional policy instead:

```bash
aws iam attach-role-policy \
  --role-name emirates-demo-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
```

The script prints the role ARN and attached policies. You can also verify them
manually:

```bash
aws iam get-role \
  --role-name emirates-demo-eks-node-role

aws iam list-attached-role-policies \
  --role-name emirates-demo-eks-node-role
```

Select `emirates-demo-eks-node-role` as the node IAM role when creating the
managed node group. Place the node group in the private subnets.
