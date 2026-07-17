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

## Replica identity preflight

Before streaming, Mammoth inspects every table included by the configured
publications. A table needs usable replica identity whenever any configured
publication enables `UPDATE` or `DELETE` for it. Mammoth accepts PostgreSQL's
supported identity modes:

- the default identity with a usable primary key;
- an eligible unique index selected by `REPLICA IDENTITY USING INDEX`; or
- `REPLICA IDENTITY FULL`.

An insert-only publication does not require old-row identity. Mammoth reports
all invalid schema-qualified tables and publication actions together, then
fails before decoding or delivery.

The same catalog snapshot supplies each relation's ordered identity columns to
`pgoutput-source-adapter` 0.3.0. Default identity uses primary-key column order,
`USING INDEX` uses the selected index order, and `FULL` uses all live table
columns in PostgreSQL attribute order. Mammoth keys the mapping by relation OID
and schema-qualified table; the adapter remains responsible for extracting and
representing complete composite or non-`id` keys. If a configured identity
column is absent from decoded row values, normalization fails instead of
emitting a partial key.

Preferred remediation is a stable primary key. Existing schemas may select an
eligible unique, non-partial, non-null index:

```sql
ALTER TABLE public.orders REPLICA IDENTITY USING INDEX orders_external_id_key;
```

As an explicit tradeoff, full-row identity is also valid but increases WAL
volume and may make downstream matching more expensive:

```sql
ALTER TABLE public.orders REPLICA IDENTITY FULL;
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

## Slot readiness and retained WAL

The separate `mammoth observability CONFIG` process performs read-only slot
inspection for `/readyz` and `/metrics`. Readiness requires the configured slot
to exist, be active, retain a restart LSN, and have no loss, conflict, or
invalidation state.

Prometheus exposes `mammoth_postgres_slot_retained_wal_bytes`,
`mammoth_postgres_slot_safe_wal_size_bytes`, `mammoth_postgres_slot_wal_status`,
activity/readiness gauges, inactivity time, and numeric restart and
confirmed-flush LSN positions. Alert on inspection failure, missing or unready
slots, and retained WAL growth appropriate to the PostgreSQL volume. Mammoth
reports these facts; deployment infrastructure remains responsible for disk
capacity alerts.

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

## Real integration tests

The E2E task always exercises the HTTP, SQLite, and filesystem delivery path.
Set `MAMMOTH_E2E_POSTGRES_URL` to also exercise Mammoth against a disposable
PostgreSQL instance:

```bash
MAMMOTH_E2E_POSTGRES_URL=postgres://postgres:postgres@127.0.0.1:5432/mammoth_e2e \
  bundle exec rake test:e2e
```

The real PostgreSQL suite covers `INSERT`, `UPDATE`, and `DELETE` in one
transaction with a composite replica identity, replication-connection
recovery, contiguous checkpoint and acknowledgement advancement after
out-of-order completion, and fail-closed slot invalidation.

Configure the fixture with `wal_level=logical`. The test role must be able to
create publications and logical replication slots, terminate replication
backends, and change `max_slot_wal_keep_size`. Use an isolated, disposable
database because the suite intentionally creates and invalidates slots and
generates WAL pressure.
