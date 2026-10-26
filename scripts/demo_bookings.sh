#!/usr/bin/env bash
# Flight booking demo: index management, querying, and shard placement.
#
# Usage:
#   ES_URL=https://es.example.internal:9200 ES_USER=elastic ES_PASS=... \
#     ES_INSECURE=true ./scripts/demo_bookings.sh --create
#   ES_URL=... ES_USER=elastic ES_PASS=... ES_CACERT=/path/to/ca.crt \
#     ./scripts/demo_bookings.sh --create
#   ./scripts/demo_bookings.sh --index scripts/flight-bookings-data.json
#
# Flags:
#   --create   Install the index template, create flight-bookings-000001 and
#              the flight-bookings alias (skipped if they already exist), then
#              print shard placement by zone. Use --data-file to load documents.
#   --index    Bulk-index a JSON array of booking documents.
#   --query    Query the flight-bookings alias. Supports --size, --match, and
#              --pretty.
#
# Query examples:
#   ./scripts/demo_bookings.sh --query
#   ./scripts/demo_bookings.sh --query --size 10 --pretty
#   ./scripts/demo_bookings.sh --query --match origin=DXB --match destination=LHR

set -euo pipefail

ES_URL="${ES_URL:-http://localhost:9200}"
INDEX="flight-bookings-000001"
ALIAS="flight-bookings"
TEMPLATE_NAME="flight-bookings"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/flight-bookings-template.json"
DATA_FILE=""

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but was not found in PATH" >&2
  exit 1
fi

# ECK's generated certificate does not include an external LoadBalancer
# hostname, so ES_INSECURE=true is needed when connecting through that hostname.
TLS=()
if [[ "${ES_INSECURE:-false}" == "true" ]]; then
  TLS=(-k)
elif [[ -n "${ES_CACERT:-}" ]]; then
  TLS=(--cacert "${ES_CACERT}")
fi

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
  curl -sS --fail-with-body "${TLS[@]}" "${AUTH[@]}" -X "$method" "${ES_URL}${path}" \
    -H 'Content-Type: application/json' "$@"
  echo
}

cmd_create() {
  echo "==> Preflight: cluster health"
  es GET "/_cluster/health" | jq '{status, number_of_nodes, active_shards}'

  echo "==> Installing index template '${TEMPLATE_NAME}'"
  es PUT "/_index_template/${TEMPLATE_NAME}" --data-binary "@${TEMPLATE_FILE}" | jq -c .

  local status
  status="$(curl -s -o /dev/null -w '%{http_code}' "${TLS[@]}" "${AUTH[@]}" "${ES_URL}/${INDEX}")"
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

cmd_query() {
  local query_filters='[]'
  local match field value
  for match in "${QUERY_MATCHES[@]}"; do
    field="${match%%=*}"
    value="${match#*=}"
    query_filters="$(jq -c --arg field "$field" --arg value "$value" \
      '. + [{term: {($field): $value}}]' <<<"$query_filters")"
  done

  local body
  if [[ "${#QUERY_MATCHES[@]}" -eq 0 ]]; then
    body="$(jq -n --argjson size "$QUERY_SIZE" \
      '{size: $size, query: {match_all: {}}}')"
  else
    body="$(jq -n --argjson size "$QUERY_SIZE" --argjson filters "$query_filters" \
      '{size: $size, query: {bool: {filter: $filters}}}')"
  fi

  echo "==> Querying alias '${ALIAS}'"
  if [[ "$QUERY_PRETTY" == "true" ]]; then
    es POST "/${ALIAS}/_search" --data "$body" | jq .
  else
    es POST "/${ALIAS}/_search" --data "$body" | jq -c .
  fi
}

cmd_index() {
  [[ -n "$DATA_FILE" && -f "$DATA_FILE" ]] || {
    echo "--index requires an existing JSON file" >&2
    exit 1
  }
  jq -e 'type == "array" and all(.[]; type == "object")' "$DATA_FILE" >/dev/null || {
    echo "Index input must be a JSON array of objects: ${DATA_FILE}" >&2
    exit 1
  }

  local bulk_response
  echo "==> Indexing documents from '${DATA_FILE}' into alias '${ALIAS}'"
  bulk_response="$(
    jq -c --arg index "$ALIAS" '
      .[] | {"index": {"_index": $index}}, .
    ' "$DATA_FILE" |
    curl -sS --fail-with-body "${TLS[@]}" "${AUTH[@]}" \
      -X POST "${ES_URL}/_bulk" \
      -H 'Content-Type: application/x-ndjson' \
      --data-binary @-
  )"
  jq '{took, errors, indexed: ([.items[] | select(.index.status >= 200 and .index.status < 300)] | length), failed: ([.items[] | select(.index.status < 200 or .index.status >= 300)] | length)}' \
    <<<"$bulk_response"
  if jq -e '.errors == true' <<<"$bulk_response" >/dev/null; then
    echo "Bulk indexing returned one or more item errors" >&2
    jq '.items[] | select(.index.error != null)' <<<"$bulk_response" >&2
    exit 1
  fi
}

usage() {
  cat >&2 <<'EOF'
Usage:
  demo_bookings.sh --create [--data-file FILE]
  demo_bookings.sh --index FILE
  demo_bookings.sh --query [--size N] [--match FIELD=VALUE]... [--pretty]
EOF
}

COMMAND="${1:-}"
shift || true
QUERY_SIZE=10
QUERY_PRETTY=false
QUERY_MATCHES=()

if [[ "$COMMAND" == "--index" ]]; then
  DATA_FILE="${1:-}"
  [[ -n "$DATA_FILE" ]] || {
    echo "--index requires a JSON file" >&2
    exit 1
  }
  shift
fi

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --data-file)
      [[ "$#" -ge 2 ]] || {
        echo "--data-file requires a path" >&2
        exit 1
      }
      DATA_FILE="$2"
      shift 2
      ;;
    --size)
      [[ "$#" -ge 2 && "$2" =~ ^[0-9]+$ ]] || {
        echo "--size requires a non-negative integer" >&2
        exit 1
      }
      QUERY_SIZE="$2"
      shift 2
      ;;
    --match)
      [[ "$#" -ge 2 && "$2" == *=* && "${2%%=*}" != "" ]] || {
        echo "--match requires FIELD=VALUE" >&2
        exit 1
      }
      QUERY_MATCHES+=("$2")
      shift 2
      ;;
    --pretty)
      QUERY_PRETTY=true
      shift
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

case "$COMMAND" in
  --create)
    [[ "${#QUERY_MATCHES[@]}" -eq 0 && "$QUERY_SIZE" == "10" && "$QUERY_PRETTY" == "false" ]] || {
      echo "--size, --match, and --pretty are only valid with --query" >&2
      exit 1
    }
    cmd_create
    [[ -z "$DATA_FILE" ]] || cmd_index
    ;;
  --index)
    [[ "${#QUERY_MATCHES[@]}" -eq 0 && "$QUERY_SIZE" == "10" && "$QUERY_PRETTY" == "false" ]] || {
      echo "--size, --match, and --pretty are only valid with --query" >&2
      exit 1
    }
    cmd_index
    ;;
  --query)
    cmd_query
    ;;
  *)
    usage
    exit 1
    ;;
esac
