# Mammoth

[![Gem Version](https://badge.fury.io/rb/mammoth.svg)](https://badge.fury.io/rb/mammoth)
[![CI](https://github.com/kanutocd/mammoth/workflows/CI/badge.svg)](https://github.com/kanutocd/mammoth/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Mammoth is a self-hosted PostgreSQL event relay focused on reliable delivery
of database change events.

```text
PostgreSQL
      ↓
CDC Ecosystem source adapter
      ↓
CDC::Core::ChangeEvent
      ↓
Mammoth
      ↓
Webhook
```

Mammoth is intentionally boring infrastructure. It uses YAML configuration,
JSON Schema validation, local SQLite operational state, and the CDC Ecosystem's
shared vocabulary so operators can inspect, recover, and reason about delivery.

## OSS MVP

Mammoth OSS includes:

- CLI foundation
- YAML configuration loading
- JSON Schema-backed configuration validation
- SQLite operational memory bootstrap
- checkpoint persistence
- dead letter persistence
- webhook delivery sink
- delivery worker with retry, checkpoint, and DLQ handling
- CDC-core event serialization boundary
- CDC Ecosystem source-adapter integration boundary
- Docker image support
- public Helm chart support
- unit and e2e test tasks

## Boundary

Mammoth begins at CDC-core work items and ends at webhook delivery.

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

## CLI

```bash
bundle exec ./exe/mammoth version
bundle exec ./exe/mammoth validate config/mammoth.example.yml
bundle exec ./exe/mammoth bootstrap config/mammoth.example.yml
bundle exec ./exe/mammoth status config/mammoth.example.yml
bundle exec ./exe/mammoth start config/mammoth.example.yml
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
