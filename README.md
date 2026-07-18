<p align="center">
  <img src="https://raw.githubusercontent.com/kanutocd/mammoth/main/docs/assets/logo/mammoth-horizontal.svg" alt="Mammoth" width="520">
</p>

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
CDC::Core::TransactionEnvelope
      ↓
Mammoth
      ↓
Webhook fanout
```

Mammoth is intentionally boring infrastructure. It uses YAML configuration,
JSON Schema validation, local SQLite operational state, and the CDC Ecosystem's
shared vocabulary so operators can inspect, recover, and reason about delivery.

## Documentation

Documentation site:

https://kanutocd.github.io/mammoth/

API documentation:

https://kanutocd.github.io/mammoth/Mammoth.html

## Start Here

The recommended first-run experience is the
[`webhooks-quickstart`](webhooks-quickstart) stack. One Compose command starts a
demo application, logical-replication-enabled PostgreSQL, Mammoth, a signed
webhook receiver with visible retries, and Mammoth health endpoints:

```bash
cd webhooks-quickstart
docker compose up --build --wait
```

Once the flow is visible, follow its
[`ADAPTING.md`](webhooks-quickstart/ADAPTING.md) guide to connect Mammoth to an
existing PostgreSQL application.

## v1.0 Release Scope

Mammoth 1.0 includes:

- operator CLI for validation, bootstrap, status, delivery, observability, and
  dead-letter workflows
- YAML configuration loading
- JSON Schema-backed configuration validation
- SQLite operational memory bootstrap
- checkpoint persistence
- dead letter persistence
- delivered-envelope ledger persistence
- webhook delivery sink
- webhook fanout to multiple destinations
- fanout route filters by schema, table, and operation
- per-destination enable/disable and retry policy controls
- delivery worker with retry, delivered-ledger, and DLQ handling
- contiguous delivery watermark for checkpoint and PostgreSQL acknowledgement
- source-owned transport LSN preservation independent of payload `commit_lsn`
- fail-closed PostgreSQL slot and checkpoint continuity preflight
- fail-closed publication replica-identity preflight for `UPDATE` and `DELETE`
- dead-letter inspection and filtered replay commands
- CDC-core event serialization boundary
- CDC Ecosystem source-adapter integration boundary
- Docker image support
- public Helm chart support
- unit and e2e test tasks
- health, PostgreSQL slot readiness, and retained-WAL metrics endpoints
- canonical CDC dispatch counters through a `CDC::Core::Observer`
- explicit extension registries for state, destination, and runtime adapters
- node identity and local capability reporting
- lifecycle hooks, configuration providers, and reusable local command objects

## Feature Examples

The runnable examples are organized around production behaviors and failure
modes, not isolated API snippets.

| Example | v1 capability demonstrated |
| --- | --- |
| [`live_postgres_webhook`](examples/live_postgres_webhook) | End-to-end PostgreSQL logical replication into webhook delivery. |
| [`transaction_webhook`](examples/transaction_webhook) | TransactionEnvelope preservation through the concurrent runtime. |
| [`webhook_fanout`](examples/webhook_fanout) | Routed multi-destination fanout, environment-backed headers, signing, and independent retry policies. |
| [`ordering`](examples/ordering) | Ordered and throughput-oriented transaction scheduling. |
| [`checkpoint_recovery`](examples/checkpoint_recovery) | Durable restart recovery, replay suppression, checkpointing, and acknowledgement. |
| [`slot_invalidation_recovery`](examples/slot_invalidation_recovery) | Fail-closed slot invalidation and explicit operator reconciliation. |
| [`composite_replica_identity`](examples/composite_replica_identity) | Composite, non-`id` replica identity across `INSERT`, `UPDATE`, and `DELETE`. |
| [`postgres_observability`](examples/postgres_observability) | Slot readiness and Prometheus metrics correlated with PostgreSQL catalogs. |
| [`schema_evolution`](examples/schema_evolution) | Consumer-first additive schema evolution without implying DDL delivery. |
| [`destination_idempotency`](examples/destination_idempotency) | Atomic destination-side duplicate suppression across isolated relay ledgers. |
| [`failing_webhook_retry`](examples/failing_webhook_retry) | Retry exhaustion and durable dead-letter persistence. |
| [`operational_state`](examples/operational_state) | Inspectable checkpoints, delivered ledgers, and dead letters. |
| [`kubernetes_helm`](examples/kubernetes_helm) | Single-consumer Kubernetes deployment using the public Helm chart. |

See [`examples/README.md`](examples/README.md) for the complete index, boundary
notes, and commands.

## v1 Compatibility

Mammoth 1.x treats its validated configuration, serialized webhook envelopes,
documented CLI command behavior, and forward operational-state migrations as
supported contracts. Compatible minor releases may add optional configuration
or payload fields, but do not remove or reinterpret existing fields.

Human-readable CLI formatting and PostgreSQL-derived row columns are not frozen:
scripts should rely on documented exit behavior, while receivers must tolerate
additive fields and coordinate source schema changes. See
[`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) for the complete promise and
major-version boundaries. See
[`docs/WEBHOOK-PAYLOADS.md`](docs/WEBHOOK-PAYLOADS.md) for the canonical event
and transaction JSON contracts, column-change semantics, and event-ID behavior.

## Boundary

Mammoth begins at CDC-core work items and ends at webhook fanout delivery.

Mammoth does not own pgoutput protocol parsing, value decoding, source
normalization, or core dispatch vocabulary. Those belong to upstream CDC
Ecosystem components. Mammoth selects and composes a delivery runtime while
delegating its scheduling mechanics to the runtime layer. The runtime registry
wraps the selected adapter with configured batch accumulation; `Application`
only streams core work and coordinates lifecycle flush and shutdown calls.

For the live PostgreSQL stream, `pgoutput-source-adapter` incrementally owns
`Begin`/`Commit` buffering and emits exact `CDC::Core::ChangeEvent` or
`CDC::Core::TransactionEnvelope` work items. Mammoth only composes the
transport, parser, decoder, and source adapter and forwards the resulting core
work to delivery. Mammoth's publication preflight supplies ordered,
catalog-derived replica-identity columns to the adapter, which owns composite
and non-`id` key extraction.

At the downstream boundary, `Mammoth::DeliveryProcessor` implements
`CDC::Core::Processor` and returns `CDC::Core::ProcessorResult`. Inline and
concurrent runtimes notify a `CDC::Core::Observer`; Mammoth's default observer
maps the canonical started, succeeded, failed, and skipped notifications to
Prometheus counters.

`Mammoth::ReplicationConsumer` accepts only exact core events and transaction
envelopes. Operator-facing JSON, such as `deliver-sample` input and persisted
dead letters, is reconstructed by `PersistedPayloadDeserializer` before it
re-enters delivery; stored hashes do not masquerade as live CDC work.

## Extensions

Mammoth OSS exposes small adapter registries for future extensions:

- operational state adapters
- destination adapters
- runtime adapters
- lifecycle hooks
- configuration providers
- local command objects

See [`docs/EXTENSIONS.md`](docs/EXTENSIONS.md).

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

Reconstruct and deliver a single persisted event JSON file through Mammoth's
core delivery path:

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

SQLite is the built-in default behind `operational_state.adapter`. Bootstrap,
status, observability, and dead-letter commands consume the adapter contract
rather than opening SQLite directly.

## Performance

Mammoth includes local benchmarks for the product surfaces operators tune in
production:

- event and transaction serialization, including deterministic fallback IDs
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
filesystem paths. Set `MAMMOTH_E2E_POSTGRES_URL` to include the real PostgreSQL
logical-replication scenarios:

```bash
MAMMOTH_E2E_POSTGRES_URL=postgres://postgres:postgres@127.0.0.1:5432/mammoth_e2e \
  bundle exec rake test:e2e
```

The PostgreSQL fixture must have `wal_level=logical`; its test role must be able
to create publications and logical replication slots, terminate replication
backends, and change `max_slot_wal_keep_size`.

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

Production operators should also monitor retained WAL and slot readiness,
configure PostgreSQL retention guardrails, and alert on database disk and
catalog health. DDL and sequence state are not replicated; coordinate schema
changes with webhook consumers and synchronize sequences externally when
building a writable database copy. See
[`docs/POSTGRESQL.md`](docs/POSTGRESQL.md) and
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

## License

Mammoth OSS is licensed under the [MIT License](LICENSE.txt).
