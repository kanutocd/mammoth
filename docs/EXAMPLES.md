# Examples

Mammoth ships examples that validate different parts of the system.

## `examples/postgres_webhook`

Purpose:

```text
sample CDC-shaped event
    ↓
Mammoth delivery path
    ↓
webhook receiver
```

Use this when you want a deterministic happy-path delivery demo without running logical replication.

## `examples/live_postgres_webhook`

Purpose:

```text
PostgreSQL INSERT
    ↓
logical replication
    ↓
Mammoth
    ↓
webhook receiver
```

Use this when you want to validate the real PostgreSQL ingestion path.

This example exercises:

- PostgreSQL logical replication
- pgoutput-client transport
- replication slot usage
- publication subscription
- webhook delivery
- idle replication behavior


## `examples/transaction_webhook`

Purpose:

```text
PostgreSQL transaction
    ↓
logical replication
    ↓
TransactionEnvelope
    ↓
CDC::Concurrent::ProcessorPool
    ↓
webhook receiver
```

Use this when you want to validate Mammoth transaction-level delivery.

This example exercises:

- PostgreSQL logical replication
- transaction envelope preservation
- `delivery.unit: transaction`
- `runtime.adapter: concurrent`
- webhook transaction payloads
- transaction-level checkpoint boundary foundations

Run it with:

```bash
cd examples/transaction_webhook
docker compose up --build
```

The receiver should log a `transaction.committed` payload with multiple row-level
events in the `events` array.

## `examples/webhook_fanout`

Purpose:

```text
sample CDC-shaped event or TransactionEnvelope
    ↓
Mammoth fanout delivery path
    ↓
primary webhook + audit webhook
```

Use this when you want to inspect the `destinations` configuration shape for
multi-destination webhook fanout. The example is config-only: it demonstrates
the YAML contract, per-destination env-backed Authorization headers, and
per-destination HMAC signing secrets without adding another Docker stack.

This example exercises:

- `destinations`
- multiple webhook destinations
- per-destination `header_env`
- per-destination `signing.secret_env`
- independent destination names used by delivered ledgers and dead letters

Validate the config with:

```bash
bundle exec ./exe/mammoth validate examples/webhook_fanout/config/mammoth.yml
```

## `examples/ordering`

Purpose:

```text
PostgreSQL transactions A, B, C
    ↓
TransactionEnvelope delivery
    ↓
cdc-concurrent scheduling
    ↓
preserve_order true vs false
```

Use this to validate the operational tradeoff controlled by:

```yaml
runtime:
  adapter: concurrent
  concurrency: 25
  preserve_order: true
```

With `preserve_order: true`, the receiver should complete transactions in commit order:

```text
A
B
C
```

With `preserve_order: false`, the receiver intentionally makes transaction `A` slow, so `B` and `C` may complete first. This demonstrates the throughput-oriented mode where strict delivery order is not guaranteed.

Run the default ordered example:

```bash
cd examples/ordering
docker compose down -v
docker compose up --force-recreate --build
```

Run the unordered variant:

```bash
cd examples/ordering
docker compose down -v
MAMMOTH_ORDERING_CONFIG=./config/preserve_order_false.yml \
  docker compose up --force-recreate --build
```

## `examples/operational_state`

Purpose:

```text
Mammoth bootstrap
    ↓
SQLite operational database
    ↓
checkpoints + dead_letters schema
```

Use this when you want to inspect Mammoth's local operational memory without running PostgreSQL or a webhook receiver.

Useful commands:

```bash
bundle exec ./exe/mammoth bootstrap examples/operational_state/config/mammoth.yml
bundle exec ./exe/mammoth status examples/operational_state/config/mammoth.yml
sqlite3 examples/operational_state/.sqlite3/mammoth.db ".tables"
```

## `examples/failing_webhook_retry`

Purpose:

```text
sample CDC-shaped event
    ↓
Mammoth delivery worker
    ↓
webhook returns 500
    ↓
retry exhaustion
    ↓
SQLite dead letter
```

Use this to validate retry and dead-letter behavior.

After running the example, inspect the SQLite database in the Docker volume.

Expected dead-letter shape:

```text
demo-order-1|failing_webhook|insert|public|orders|2|pending|Mammoth::DeliveryError|webhook failing_webhook returned HTTP 500
```

If the same persistent volume is reused across multiple runs, repeated executions may append additional dead-letter records for the same sample event.

Clear the volume for a clean run:

```bash
docker compose down -v
```

## `examples/kubernetes_helm`

Purpose:

```text
Helm chart
    ↓
Kubernetes Deployment
    ↓
PVC-backed SQLite operational state
```

Use this to validate chart rendering, installation, and persistence wiring.

The example expects you to provide real deployment dependencies such as PostgreSQL, secrets, publications, and webhook destinations.


## Checkpoint Recovery

`examples/checkpoint_recovery` demonstrates Mammoth restart recovery using a persistent SQLite checkpoint store and permanent PostgreSQL replication slot. It validates that delivered transactions are not replayed after Mammoth restarts and that later transactions continue to flow.
