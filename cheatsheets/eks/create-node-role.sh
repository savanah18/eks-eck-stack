#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s <cluster-name>\n' "$0" >&2
  exit 2
fi

CLUSTER_NAME=$1
ROLE_NAME="${CLUSTER_NAME}-eks-node-role"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TRUST_POLICY="${SCRIPT_DIR}/node-role-trust-policy.json"

if [[ ! -f "$TRUST_POLICY" ]]; then
  printf 'Trust policy not found: %s\n' "$TRUST_POLICY" >&2
  exit 1
fi

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "file://${TRUST_POLICY}" \
  --description "IAM role for ${CLUSTER_NAME} EKS managed nodes"

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly

printf 'Created node role:\n'
aws iam get-role \
  --role-name "$ROLE_NAME" \
  --query 'Role.Arn' \
  --output text

printf '\nAttached policies:\n'
aws iam list-attached-role-policies \
  --role-name "$ROLE_NAME" \
  --query 'AttachedPolicies[].PolicyArn' \
  --output text
