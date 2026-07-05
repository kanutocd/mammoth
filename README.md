# Mammoth

[![Gem Version](https://badge.fury.io/rb/mammoth.svg)](https://badge.fury.io/rb/mammoth)
[![CI](https://github.com/kanutocd/mammoth/workflows/CI/badge.svg)](https://github.com/kanutocd/mammoth/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

🦣 Mammoth is a self-hosted PostgreSQL event relay focused on reliable delivery
of database change events.

```text
PostgreSQL
      ↓
CDC Ecosystem source adapter
      ↓
CDC::Core::TransactionEnvelope
      ↓
Mammoth
      ↓
Webhook fanout
```

🦣 Mammoth is intentionally boring infrastructure. It uses YAML configuration,
JSON Schema validation, local SQLite operational state, and the CDC Ecosystem's
shared vocabulary so operators can inspect, recover, and reason about delivery.

## Documentation

Documentation site:

https://kanutocd.github.io/mammoth/

API documentation:

https://kanutocd.github.io/mammoth/Mammoth.html


## OSS MVP

🦣 Mammoth OSS includes:

- CLI foundation
- YAML configuration loading
- JSON Schema-backed configuration validation
- SQLite operational memory bootstrap
- checkpoint persistence
- dead letter persistence
- webhook delivery sink
- webhook fanout to multiple destinations
- fanout route filters by schema, table, and operation
- per-destination enable/disable and retry policy controls
- delivery worker with retry, checkpoint, and DLQ handling
- dead-letter inspection and filtered replay commands
- CDC-core event serialization boundary
- CDC Ecosystem source-adapter integration boundary
- Docker image support
- public Helm chart support
- unit and e2e test tasks
- health and metrics endpoints

## Boundary

Mammoth begins at CDC-core work items and ends at webhook fanout delivery.

Mammoth does not own pgoutput protocol parsing, value decoding, source
normalization, ordering policy, or runtime execution. Those belong to the
upstream CDC Ecosystem components.

## Configuration

Mammoth configuration is YAML-backed and IDE-friendly.

```yaml
# yaml-language-server: $schema=./mammoth.schema.json
```

Validate configuration:

```bash
bundle exec ./exe/mammoth validate config/mammoth.example.yml
```

Fanout destinations can be routed and tuned independently:

```yaml
destinations:
  - name: audit_webhook
    type: webhook
    enabled: true
    url: https://audit.example.com/cdc
    timeout_seconds: 5
    route:
      schemas: [public]
      tables: [orders]
      operations: [insert, update]
    retry:
      max_attempts: 3
      schedule_seconds: [1, 10]
```

## CLI

```bash
bundle exec ./exe/mammoth version
bundle exec ./exe/mammoth validate config/mammoth.example.yml
bundle exec ./exe/mammoth bootstrap config/mammoth.example.yml
bundle exec ./exe/mammoth status config/mammoth.example.yml
bundle exec ./exe/mammoth start config/mammoth.example.yml
bundle exec ./exe/mammoth observability config/mammoth.example.yml
```

Deliver a single normalized event JSON file through Mammoth's delivery path:

```bash
bundle exec ./exe/mammoth deliver-sample \
  examples/postgres_webhook/config/mammoth.yml \
  examples/postgres_webhook/events/order_insert.json
```

## SQLite Operational State

Mammoth stores operational memory in SQLite:

- `schema_migrations`
- `checkpoints`
- `dead_letters`
- `delivered_envelopes`

## Performance

Mammoth includes local benchmarks for the product surfaces operators tune in
production:

- concurrent delivery runtime
- real webhook delivery
- multi-destination webhook fanout
- SQLite operational state
- observability snapshots
- DLQ replay

The historical numbers in [Benchmarks](https://github.com/kanutocd/mammoth/tree/main/docs/BENCHMARKS.md) are retained as a
snapshot, not a universal performance claim. Re-run the scripts in
[`benchmark/`](https://github.com/kanutocd/mammoth/tree/main/benchmark) on your own hardware when choosing
`runtime.concurrency`, `destinations`, SQLite storage, scrape frequency, and
DLQ replay expectations.

Create a publishable benchmark snapshot with:

```bash
bundle exec ruby benchmark/snapshot.rb
```

## E2E

```bash
bundle exec rake test:e2e
# or
script/test-e2e
```

The e2e task uses a real HTTP receiver, real SQLite database, and real
filesystem paths.

## Kubernetes

The public Helm chart lives under:

```text
charts/mammoth
```

Install example:

```bash
helm install mammoth charts/mammoth
```

The chart uses one replica and `Recreate` strategy to respect PostgreSQL's
logical replication slot constraint: one slot, one active subscriber.

## License

Mammoth OSS is licensed under the [MIT License](LICENSE.txt).
