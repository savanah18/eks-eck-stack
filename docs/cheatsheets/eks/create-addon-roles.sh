#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s <cluster-name>\n' "$0" >&2
  exit 2
fi

CLUSTER_NAME=$1
ROLE_PREFIX="${CLUSTER_NAME}-"

create_pod_identity_role() {
  local role_name=$1
  local description=$2
  local policy_arn=$3
  local trust_file

  trust_file=$(mktemp)
  trap 'rm -f "$trust_file"' RETURN

  cat > "$trust_file" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "pods.eks.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }
  ]
}
EOF

  aws iam create-role \
    --role-name "$role_name" \
    --assume-role-policy-document "file://${trust_file}" \
    --description "$description"

  aws iam attach-role-policy \
    --role-name "$role_name" \
    --policy-arn "$policy_arn"
}

create_pod_identity_role \
  "${ROLE_PREFIX}eks-vpc-cni-role" \
  "EKS Pod Identity role for the Amazon VPC CNI add-on" \
  "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"

create_pod_identity_role \
  "${ROLE_PREFIX}eks-ebs-csi-role" \
  "EKS Pod Identity role for the Amazon EBS CSI driver add-on" \
  "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

EXTERNAL_DNS_ROLE="${ROLE_PREFIX}external-dns-role"
EXTERNAL_DNS_TRUST=$(mktemp)
EXTERNAL_DNS_POLICY=$(mktemp)
trap 'rm -f "$EXTERNAL_DNS_TRUST" "$EXTERNAL_DNS_POLICY"' EXIT

cat > "$EXTERNAL_DNS_TRUST" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "pods.eks.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }
  ]
}
EOF

cat > "$EXTERNAL_DNS_POLICY" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResource"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-role \
  --role-name "$EXTERNAL_DNS_ROLE" \
  --assume-role-policy-document "file://${EXTERNAL_DNS_TRUST}" \
  --description "EKS Pod Identity role for ExternalDNS"

aws iam put-role-policy \
  --role-name "$EXTERNAL_DNS_ROLE" \
  --policy-name ExternalDNSRoute53 \
  --policy-document "file://${EXTERNAL_DNS_POLICY}"

printf '\nRole ARNs:\n'
for role in \
  "${ROLE_PREFIX}eks-vpc-cni-role" \
  "${ROLE_PREFIX}eks-ebs-csi-role" \
  "$EXTERNAL_DNS_ROLE"; do
  aws iam get-role \
    --role-name "$role" \
    --query 'Role.Arn' \
    --output text
done
