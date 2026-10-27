## Create add-on IAM roles

This creates EKS Pod Identity roles for:

- Amazon VPC CNI (`kube-system/aws-node`)
- Amazon EBS CSI driver (`kube-system/ebs-csi-controller-sa`)
- ExternalDNS (`kube-system/external-dns`)

The roles can be created before the EKS cluster exists. They use the
`pods.eks.amazonaws.com` trust principal, so they do not depend on a
cluster-specific OIDC provider. The script does not read or modify credentials
files.

```bash
chmod +x create-addon-roles.sh
./create-addon-roles.sh emirates-demo
```

Use the resulting role ARNs when configuring the EKS add-ons with EKS Pod
Identity. After the cluster is active, create associations for:

| Add-on | Namespace | Service account |
|---|---|---|
| Amazon VPC CNI | `kube-system` | `aws-node` |
| Amazon EBS CSI driver | `kube-system` | `ebs-csi-controller-sa` |
| ExternalDNS | `kube-system` | `external-dns` |

The VPC CNI and EBS CSI roles use AWS-managed policies. ExternalDNS uses a
least-privilege inline Route 53 policy and is restricted to hosted zones in the
account.