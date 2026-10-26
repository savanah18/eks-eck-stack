# Flight Bookings in Kibana Dev Tools

Open **Kibana -> Dev Tools -> Console**. Kibana sends these requests to the
Elasticsearch cluster, so the external LoadBalancer URL and `-k` are not
needed.

## Create the index and alias

Install the composable index template:

```http
PUT /_index_template/flight-bookings
{
  "index_patterns": ["flight-bookings-*"],
  "template": {
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1
    },
    "mappings": {
      "dynamic": "strict",
      "properties": {
        "@timestamp": { "type": "date" },
        "event_type": { "type": "keyword" },
        "booking_id": { "type": "keyword" },
        "pnr": { "type": "keyword" },
        "flight_number": { "type": "keyword" },
        "origin": { "type": "keyword" },
        "destination": { "type": "keyword" },
        "departure_time": { "type": "date" },
        "cabin_class": { "type": "keyword" },
        "fare_amount": { "type": "scaled_float", "scaling_factor": 100 },
        "currency": { "type": "keyword" },
        "passengers": { "type": "short" },
        "channel": { "type": "keyword" },
        "skywards_tier": { "type": "keyword" }
      }
    }
  },
  "priority": 100
}
```

Create the first concrete index and its write alias:

```http
PUT /flight-bookings-000001
{
  "aliases": {
    "flight-bookings": {
      "is_write_index": true
    }
  }
}
```

The template is applied automatically because the index name matches
`flight-bookings-*`.

## Index booking data

Use one bulk action and one document per line. The final newline is required:

```http
POST /_bulk
{ "index": { "_index": "flight-bookings" } }
{ "@timestamp": "2026-10-27T00:00:00Z", "event_type": "booking_created", "booking_id": "BK1001", "pnr": "A1B2C3", "flight_number": "EK001", "origin": "DXB", "destination": "LHR", "departure_time": "2026-11-01T08:30:00Z", "cabin_class": "business", "fare_amount": 4250.00, "currency": "USD", "passengers": 1, "channel": "web", "skywards_tier": "Gold" }
{ "index": { "_index": "flight-bookings" } }
{ "@timestamp": "2026-10-27T00:05:00Z", "event_type": "booking_created", "booking_id": "BK1002", "pnr": "D4E5F6", "flight_number": "EK202", "origin": "DXB", "destination": "JFK", "departure_time": "2026-11-02T14:15:00Z", "cabin_class": "economy", "fare_amount": 980.50, "currency": "USD", "passengers": 2, "channel": "mobile", "skywards_tier": "Silver" }
{ "index": { "_index": "flight-bookings" } }
{ "@timestamp": "2026-10-27T00:10:00Z", "event_type": "booking_created", "booking_id": "BK1003", "pnr": "G7H8J9", "flight_number": "EK404", "origin": "SIN", "destination": "DXB", "departure_time": "2026-11-03T02:45:00Z", "cabin_class": "first", "fare_amount": 7200.00, "currency": "USD", "passengers": 1, "channel": "agent", "skywards_tier": "Platinum" }
```

## Query data

Query all bookings:

```http
GET /flight-bookings/_search
{
  "size": 10,
  "query": {
    "match_all": {}
  }
}
```

Query an exact route:

```http
GET /flight-bookings/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "origin": "DXB" } },
        { "term": { "destination": "LHR" } }
      ]
    }
  }
}
```

Find one booking:

```http
GET /flight-bookings/_search
{
  "query": {
    "term": {
      "booking_id": "BK1001"
    }
  }
}
```

Count documents and inspect shard placement:

```http
GET /flight-bookings/_count
```

```http
GET /_cat/shards/flight-bookings-000001?v&h=index,shard,prirep,state,node
```
