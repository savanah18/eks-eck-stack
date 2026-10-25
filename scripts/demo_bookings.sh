#!/usr/bin/env bash
# Flight booking demo: index template, index + alias creation, and shard placement.
#
# Usage:
#   ES_URL=https://es.example.internal:9200 ./scripts/demo_bookings.sh --create
#   ES_URL=... ES_USER=elastic ES_PASS=... ./scripts/demo_bookings.sh --create
#
# Flags:
#   --create   Install the index template, create flight-bookings-000001 and
#              the flight-bookings alias (skipped if they already exist), then
#              print shard placement by zone.

set -euo pipefail

ES_URL="${ES_URL:-http://localhost:9200}"
INDEX="flight-bookings-000001"
ALIAS="flight-bookings"
TEMPLATE_NAME="flight-bookings"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/flight-bookings-template.json"

# Build curl auth args only when credentials are provided.
AUTH=()
if [[ -n "${ES_USER:-}" ]]; then
  AUTH=(-u "${ES_USER}:${ES_PASS:-}")
fi

# es <method> <path> [extra curl args...]
# Prints the response body and fails on HTTP errors.
es() {
  local method="$1" path="$2"
  shift 2
  curl -sS --fail-with-body "${AUTH[@]}" -X "$method" "${ES_URL}${path}" \
    -H 'Content-Type: application/json' "$@"
  echo
}

cmd_create() {
  echo "==> Preflight: cluster health"
  es GET "/_cluster/health" | jq '{status, number_of_nodes, active_shards}'

  echo "==> Installing index template '${TEMPLATE_NAME}'"
  es PUT "/_index_template/${TEMPLATE_NAME}" --data-binary "@${TEMPLATE_FILE}" | jq -c .

  local status
  status="$(curl -s -o /dev/null -w '%{http_code}' "${AUTH[@]}" "${ES_URL}/${INDEX}")"
  if [[ "$status" == "200" ]]; then
    echo "==> Index ${INDEX} already exists, skipping create"
  else
    echo "==> Creating index ${INDEX} with alias ${ALIAS}"
    es PUT "/${INDEX}" \
      --data "{\"aliases\": {\"${ALIAS}\": {\"is_write_index\": true}}}" | jq -c .
  fi

  echo "==> Index settings"
  es GET "/${INDEX}/_settings/index.number_of_shards,index.number_of_replicas" \
    | jq ".\"${INDEX}\".settings.index | {number_of_shards, number_of_replicas}"

  echo "==> Shard placement (primary vs replica, by node and zone)"
  local shards zones
  shards="$(es GET "/_cat/shards/${INDEX}?format=json&h=index,shard,prirep,state,node")"
  zones="$(es GET "/_cat/nodeattrs?format=json&h=node,attr,value" \
    | jq '[.[] | select(.attr == "zone")] | map({(.node): .value}) | add // {}')"
  jq -n --argjson shards "$shards" --argjson zones "$zones" '
    $shards
    | map(. + {zone: ($zones[.node] // "unknown")})
    | sort_by(.shard, .prirep)
    | .[]
    | "shard \(.shard)  \(if .prirep == "p" then "primary" else "replica" end)  \(.state)  node=\(.node)  zone=\(.zone)"
  ' -r
}

case "${1:-}" in
  --create) cmd_create ;;
  *)
    echo "Usage: $0 --create" >&2
    exit 1
    ;;
esac
