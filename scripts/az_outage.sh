#!/usr/bin/env bash
# Manual availability-zone outage drill for the Elasticsearch cluster on EKS.
#
# Simulates losing an AZ by cordoning and draining every node in that zone.
# Optionally stops the EC2 instances behind those nodes for a harder failure.
#
# Usage:
#   ZONE=eu-central-1a ./scripts/az_outage.sh status
#   ZONE=eu-central-1a ./scripts/az_outage.sh drain          # cordon + drain zone
#   ZONE=eu-central-1a ./scripts/az_outage.sh stop           # stop the zone's EC2 instances
#   ZONE=eu-central-1a ./scripts/az_outage.sh restore        # start instances, uncordon
#   ./scripts/az_outage.sh stop-node <node-name>             # stop one specific node
#   ./scripts/az_outage.sh start-node <node-name>            # start one specific node
#
# Environment:
#   ZONE         Availability zone to hit (e.g. eu-central-1a)
#   ES_NAMESPACE Namespace of the ECK cluster (default: elastic)
#   ES_CLUSTER   ECK cluster name (default: flight-es)
#   ES_USER      Elasticsearch user for health checks (default: elastic)
#   AWS_REGION   Region for EC2 calls (default: eu-central-1)
#
# Note: EBS volumes are zonal. An Elasticsearch pod whose PVC lives in the
# lost zone cannot reschedule elsewhere until the zone returns. That is the
# behaviour the demo is meant to show.

set -euo pipefail

ES_NAMESPACE="${ES_NAMESPACE:-elastic}"
ES_CLUSTER="${ES_CLUSTER:-flight-es}"
ES_USER="${ES_USER:-elastic}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-10m}"

log() { echo "==> $*"; }

require_zone() {
  if [[ -z "${ZONE:-}" ]]; then
    echo "ZONE is not set (e.g. ZONE=eu-central-1a)" >&2
    exit 1
  fi
}

# Nodes in the target zone, one name per line.
zone_nodes() {
  kubectl get nodes -l "topology.kubernetes.io/zone=${ZONE}" -o jsonpath='{.items[*].metadata.name}' \
    | tr ' ' '\n' | sed '/^$/d'
}

# EC2 instance IDs for the given node names, parsed from spec.providerID (aws:///<az>/<i-id>).
instance_ids() {
  local node
  for node in "$@"; do
    kubectl get node "$node" -o jsonpath='{.spec.providerID}' | awk -F/ '{print $NF}'
  done
}

# Run an Elasticsearch API call from inside one of the cluster's pods.
es_api() {
  local pod
  pod="$(kubectl -n "$ES_NAMESPACE" get pods -l "elasticsearch.k8s.elastic.co/cluster-name=${ES_CLUSTER}" \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
  local pass
  pass="$(kubectl -n "$ES_NAMESPACE" get secret "${ES_CLUSTER}-es-elastic-user" -o jsonpath='{.data.elastic}' | base64 -d)"
  kubectl -n "$ES_NAMESPACE" exec "$pod" -c elasticsearch -- \
    curl -sk -u "${ES_USER}:${pass}" "https://localhost:9200$1"
}

cmd_status() {
  log "Nodes by zone"
  kubectl get nodes -L topology.kubernetes.io/zone

  log "Elasticsearch pods"
  kubectl -n "$ES_NAMESPACE" get pods -l "elasticsearch.k8s.elastic.co/cluster-name=${ES_CLUSTER}" -o wide

  log "Cluster health"
  es_api "/_cluster/health?pretty"

  log "Shards (index, shard, prirep, state, node)"
  es_api "/_cat/shards?v&h=index,shard,prirep,state,node,unassigned.reason"
}

cmd_drain() {
  require_zone
  local nodes node
  nodes="$(zone_nodes)"
  if [[ -z "$nodes" ]]; then
    echo "No nodes found in zone ${ZONE}" >&2
    exit 1
  fi

  log "Cordoning nodes in ${ZONE}"
  # shellcheck disable=SC2086
  kubectl cordon $nodes

  for node in $nodes; do
    log "Draining ${node}"
    # PodDisruptionBudgets from ECK limit how many Elasticsearch pods leave at once.
    kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout="$DRAIN_TIMEOUT" \
      || echo "Drain of ${node} did not finish cleanly; check PDBs and pod status." >&2
  done
  log "Zone ${ZONE} drained. Run: ./scripts/az_outage.sh status"
}

cmd_stop() {
  require_zone
  local nodes ids
  nodes="$(zone_nodes)"
  # shellcheck disable=SC2086
  ids="$(instance_ids $nodes | tr '\n' ' ')"
  log "Stopping instances in ${ZONE}: ${ids}"
  # shellcheck disable=SC2086
  aws ec2 stop-instances --region "$AWS_REGION" --instance-ids $ids >/dev/null
  log "Stop requested. Run: ./scripts/az_outage.sh status"
}

cmd_restore() {
  require_zone
  local nodes ids
  nodes="$(zone_nodes)"
  # shellcheck disable=SC2086
  ids="$(instance_ids $nodes | tr '\n' ' ')"
  log "Starting instances in ${ZONE}: ${ids}"
  # shellcheck disable=SC2086
  aws ec2 start-instances --region "$AWS_REGION" --instance-ids $ids >/dev/null
  log "Uncordoning nodes in ${ZONE}"
  # shellcheck disable=SC2086
  kubectl uncordon $nodes
  log "Restore requested. Watch recovery with: ./scripts/az_outage.sh status"
}

cmd_stop_node() {
  local node="$1" id
  id="$(instance_ids "$node")"
  log "Stopping ${node} (${id})"
  aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "$id" >/dev/null
}

cmd_start_node() {
  local node="$1" id
  id="$(instance_ids "$node")"
  log "Starting ${node} (${id})"
  aws ec2 start-instances --region "$AWS_REGION" --instance-ids "$id" >/dev/null
  kubectl uncordon "$node"
}

case "${1:-}" in
  status)     cmd_status ;;
  drain)      cmd_drain ;;
  stop)       cmd_stop ;;
  restore)    cmd_restore ;;
  stop-node)  [[ -n "${2:-}" ]] || { echo "Usage: $0 stop-node <node>" >&2; exit 1; }; cmd_stop_node "$2" ;;
  start-node) [[ -n "${2:-}" ]] || { echo "Usage: $0 start-node <node>" >&2; exit 1; }; cmd_start_node "$2" ;;
  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
