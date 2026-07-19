<!--
# @title PostgreSQL Requirements
-->

# PostgreSQL Requirements

Mammoth consumes PostgreSQL logical replication through the CDC ecosystem's pgoutput path.

## Supported PostgreSQL versions

Mammoth supports PostgreSQL 14 through PostgreSQL 18, inclusive. These are the
PostgreSQL major versions currently maintained by the PostgreSQL community and
covered by Mammoth's real logical-replication E2E compatibility matrix.

Mammoth supports PostgreSQL major versions that are both maintained by the
PostgreSQL community and included in Mammoth's compatibility test matrix. New
PostgreSQL majors are unsupported until explicitly tested and documented. EOL
versions may be removed from the supported range in a subsequent Mammoth minor
release with release-note notice.

PostgreSQL 19 is a development release and is not supported.

## PostgreSQL settings

The PostgreSQL server must allow logical replication:


```text
wal_level = logical
max_replication_slots = 10
max_wal_senders = 10
```

The exact values depend on your deployment, but `wal_level=logical` is mandatory.

### Server-side WAL retention guardrails

Set `max_slot_wal_keep_size` to a value appropriate for the database volume and
recovery budget. `idle_replication_slot_timeout` is available only in
PostgreSQL 18 and can invalidate slots that remain inactive too long. PostgreSQL
14 through 17 do not provide this setting. These settings protect PostgreSQL
from unbounded retention; they do not preserve Mammoth delivery continuity. When a guardrail invalidates a slot,
Mammoth fails closed and requires external backfill or reconciliation before
new operational state is established.

Mammoth reports retained WAL and slot health, but PostgreSQL disk-capacity,
archive, and catalog-XID alerts remain deployment-infrastructure
responsibilities.

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
`pgoutput-source-adapter` 0.3.1. Default identity uses primary-key column order,
`USING INDEX` uses the selected index order, and `FULL` uses all live table
columns in PostgreSQL attribute order. Mammoth keys the mapping by relation OID
and schema-qualified table; the adapter remains responsible for extracting and
representing complete composite or non-`id` keys. If a configured identity
column is absent from decoded row values, normalization fails instead of
emitting a partial key.

The adapter also assigns each row change a stable, zero-based transaction-local
sequence number. Mammoth includes that discriminator in deterministic event-ID
generation, so two otherwise identical changes at the same source position
remain distinct while replaying the transaction reproduces the same IDs.

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
  confirmed_flush_lsn,
  pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_wal_bytes,
  wal_status,
  safe_wal_size,
  inactive_since,
  conflicting,
  invalidation_reason,
  catalog_xmin
FROM pg_replication_slots
WHERE slot_type = 'logical';
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
capacity and catalog-XID age alerts.

The columns available in `pg_replication_slots` vary by PostgreSQL version.
In particular, `inactive_since` and `invalidation_reason` are available from
PostgreSQL 17, while PostgreSQL 16 exposes `conflicting` but not those newer
fields. PostgreSQL 18 can additionally report `idle_timeout` as an
`invalidation_reason`. Mammoth's production inspection path is version-tolerant
and treats unavailable fields as absent. For manual SQL, remove fields that do
not exist on the server version being inspected.

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

## DDL and schema evolution

PostgreSQL logical replication does not emit DDL or replicate schema
definitions. Relation metadata may refresh after a table change, but Mammoth
does not deliver the migration itself, negotiate a schema version, update a
downstream schema, or guarantee that a payload-shape change is compatible with
existing webhook consumers.

Coordinate migrations with every destination. Prefer additive,
backward-compatible rollouts:

1. make consumers accept both old and new payload shapes;
2. apply the PostgreSQL migration;
3. deploy producers that rely on the new shape; and
4. remove old-shape support only after the retained WAL and retry windows have
   passed.

Renaming or removing columns, changing types, or changing replica identity
requires an explicit compatibility and recovery plan. Re-run configuration and
startup preflight after publication or replica-identity changes.

## Sequences

Logical replication does not replicate sequence state. Generated values that
are stored in inserted rows are delivered as ordinary row values, which is
sufficient for normal webhook consumers. A destination being built as a
writable database replica or failover target must synchronize its sequences
separately before accepting writes.

## Destination conflicts and idempotency

Mammoth is not a PostgreSQL subscription that applies SQL to a subscriber, so
native subscriber conflicts such as duplicate-key apply failures do not map
directly to Mammoth. Mammoth sends HTTP payloads, retries unsuccessful
deliveries, records exhausted failures in the dead-letter store, and uses its
delivered-envelope ledger to suppress duplicate delivery.

Destinations must enforce their own idempotency and interpret semantic
conflicts. Inspect and replay dead letters only after correcting the
destination-side condition; Mammoth does not merge rows or choose a conflict
winner.

## PostgreSQL upgrades and slot lifecycle

Treat database upgrades, slot renames, slot drops, and changes to
`replication.slot` as continuity-sensitive operations. Some PostgreSQL versions
can migrate eligible logical slots through `pg_upgrade`, subject to PostgreSQL
version and configuration restrictions; do not assume either that every
upgrade preserves a slot or that every upgrade drops it.

After an upgrade, verify the slot plugin, database, restart LSN, confirmed flush
LSN, WAL status, invalidation state, and Mammoth checkpoint before starting the
relay. Never create a replacement slot and reuse an older Mammoth checkpoint as
though it represented the same retained WAL history.

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
