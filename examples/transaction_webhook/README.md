# Mammoth Transaction Webhook Demo

This example demonstrates Mammoth transaction-level delivery:

```text
PostgreSQL transaction
      ↓
logical replication
      ↓
TransactionEnvelope
      ↓
CDC::Concurrent::ProcessorPool
      ↓
webhook transaction payload
```

Unlike the basic live PostgreSQL example, this config uses:

```yaml
delivery:
  unit: transaction
  ordering:
    scope: transaction

runtime:
  adapter: concurrent
  concurrency: 1
  preserve_order: true
```

The webhook receiver gets one `transaction.committed` payload containing all
row-level events committed by the SQL transaction.

## Run

```bash
docker compose up --build
```

The compose file starts:

- PostgreSQL with `wal_level=logical`
- a Ruby webhook receiver
- Mammoth running `start`
- a SQL producer that commits multiple row changes in a single transaction

## Expected receiver output

The receiver logs a transaction payload similar to:

```text
payload type: transaction.committed
transaction_id: ...
source_position: ...
event_count: 4
event[0]: insert orders ...
event[1]: insert orders ...
event[2]: update orders ...
event[3]: update orders ...
```

The exact transaction id, source position, and identity payload depend on
PostgreSQL and the source adapter output.

## Why this matters

Transaction delivery gives downstream consumers one committed transaction
payload. Mammoth's progress boundary is safe in both event and transaction
delivery modes:

```text
receive WAL
  ↓
pgoutput-source-adapter emits the committed TransactionEnvelope
  ↓
record a durable outcome for every destination
  ↓
advance the contiguous delivery watermark
  ↓
persist the checkpoint
  ↓
acknowledge the same position through pgoutput-client
```

Successful delivery, an existing duplicate ledger record, an intentional route
or disabled-destination skip, and a persisted dead letter are durable outcomes.
Concurrent completion cannot advance the checkpoint or PostgreSQL
acknowledgement past earlier incomplete committed work.

Mammoth does not buffer `Begin`/`Commit` messages in this path. The
`pgoutput-source-adapter` streaming API owns transaction state and yields an
exact `CDC::Core::TransactionEnvelope` to Mammoth.

## Operational note

Logical replication slots allow one active subscriber per slot. This example
uses one Mammoth process and one replication slot named `mammoth_transaction`.
Downstream delivery concurrency does not create additional replication slots or
replication connections.

## Clean up

```bash
docker compose down -v
```
