```
aws iam create-role --role-name emirates-demo-eks-cluster-iam-role --assume-role-policy-document file://eks-cluster-role-trust-policy.json
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name emirates-demo-eks-cluster-iam-role
```