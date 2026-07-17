# PostgreSQL Requirements

Mammoth consumes PostgreSQL logical replication through the CDC ecosystem's pgoutput path.

## PostgreSQL settings

The PostgreSQL server must allow logical replication:

```text
wal_level = logical
max_replication_slots = 10
max_wal_senders = 10
```

The exact values depend on your deployment, but `wal_level=logical` is mandatory.

## Publication

Mammoth requires at least one publication listed in configuration.

Example:

```sql
CREATE TABLE IF NOT EXISTS orders (
  id bigserial PRIMARY KEY,
  status text NOT NULL,
  total_cents integer NOT NULL
);

CREATE PUBLICATION mammoth_publication FOR TABLE orders;
```

Check publications:

```sql
SELECT * FROM pg_publication;
```

## Replication slot

Mammoth consumes one logical replication slot per active stream.

Example configuration:

```yaml
replication:
  slot: mammoth_prod
  publications:
    - mammoth_publication
  auto_create_slot: true
  temporary_slot: false
  feedback_interval: 10.0
```

If `auto_create_slot` is `true`, Mammoth may create a missing slot for a fresh
stream. If a configured `start_lsn` or persisted checkpoint exists, automatic
creation is disabled and a missing slot fails closed. If `auto_create_slot` is
`false`, create the slot yourself.

Inspect slots:

```sql
SELECT
  slot_name,
  plugin,
  slot_type,
  database,
  active,
  restart_lsn,
  confirmed_flush_lsn
FROM pg_replication_slots;
```

Expected plugin:

```text
pgoutput
```

## Slot and checkpoint preflight

Mammoth inspects the configured slot through pgoutput-client before opening the
replication stream. Startup fails before decoding or delivery when:

- the slot is missing and first-time automatic creation is not safe;
- the slot is active in another process;
- the slot is not a logical `pgoutput` slot for the configured database;
- `wal_status` is `lost` or `unreserved`;
- PostgreSQL reports a conflict or invalidation reason;
- the slot has no reachable `restart_lsn`; or
- `restart_lsn` or `confirmed_flush_lsn` has advanced beyond Mammoth's
  configured or persisted resume LSN.

Mammoth never treats a replacement slot as continuation of a durable
checkpoint. Lost continuity requires an external backfill or reconciliation,
followed by establishment of new safe operational state. Temporary slots are
rejected when durable checkpoint recovery is requested.

## One slot, one active subscriber

A PostgreSQL logical replication slot is consumed by one active subscriber at a time. Run one active Mammoth replica per logical replication slot.

For Kubernetes, this is why the Helm chart defaults to one replica.

## Idle streams and feedback

Mammoth uses pgoutput-client transport behavior that sends replication feedback during idle periods. The `replication.feedback_interval` setting controls the feedback cadence.

The acknowledged feedback position is not the latest position Mammoth has
received. Mammoth first records a durable outcome for every destination and
advances only the contiguous delivery watermark. It writes that watermark to
the checkpoint store before acknowledging the same position to pgoutput-client.
Concurrent completion therefore cannot skip unfinished earlier work.

The progress watermark comes from pgoutput-client's transport metadata
(`XLogData#wal_end_lsn`). It is preserved separately while
pgoutput-source-adapter yields exact CDC-core work. A normalized transaction's
`commit_lsn` remains payload context and may be the decoder's decimal value; it
is never substituted for the acknowledgement-compatible transport LSN.

The durable outcomes that permit progress are:

- successful delivery recorded in the delivered-envelope ledger;
- a duplicate already present in that ledger;
- an intentional disabled-destination or route-filter skip;
- retry exhaustion persisted in the dead-letter store.

An exception before one of those outcomes leaves a gap and prevents later work
from advancing the checkpoint or PostgreSQL acknowledgement. Event delivery
also waits for every event in a source transaction before advancing.

Example:

```yaml
replication:
  feedback_interval: 7.0
```

Use a value appropriate for your PostgreSQL timeout and operational needs.
