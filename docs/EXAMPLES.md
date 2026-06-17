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

Use this when you want to validate Mammoth 0.2 transaction-level delivery.

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
