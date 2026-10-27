```
aws eks describe-cluster --region us-east-2 --name emirates-demo-eks-cluster --query "cluster.status"
aws eks update-kubeconfig --region us-east-2 --name emirates-demo-eks-cluster
```****