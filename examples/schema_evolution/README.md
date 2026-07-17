# Schema Evolution Example

This example demonstrates an additive PostgreSQL schema rollout while Mammoth
continues streaming. The receiver is deployed first with support for both
payload shapes, PostgreSQL then adds a nullable `currency` column, and a new
producer begins writing it.

```text
receiver accepts v1 and v2
          ↓
v1 INSERT → Mammoth → payload without currency
          ↓
ALTER TABLE ADD COLUMN currency
          ↓
       no DDL event
          ↓
v2 INSERT → Mammoth → payload with currency
```

PostgreSQL pgoutput refreshes relation metadata after the table changes, so
subsequent row events can include the new column. The `ALTER TABLE` statement
itself is not emitted as a change event.

## Run

Start PostgreSQL, the backward-compatible receiver, and Mammoth:

```bash
docker compose up -d --build
```

Produce a row using the original schema:

```bash
docker compose run --rm producer_v1
docker compose logs webhook_receiver
```

The receiver should report:

```text
accepted v1 event status=before_migration fields=id,status,total_cents
```

Apply the additive migration:

```bash
docker compose run --rm migrate
```

No webhook is produced by that command because logical replication does not
transport DDL. Now use the evolved schema:

```bash
docker compose run --rm producer_v2
docker compose logs webhook_receiver
```

The receiver should also report:

```text
accepted v2 event status=after_migration fields=currency,id,status,total_cents
```

## Rollout Wisdom

The safe order is:

1. deploy consumers that accept both old and new payload shapes;
2. apply an additive, backward-compatible database migration;
3. deploy producers that populate the new field; and
4. remove old-shape support only after retained WAL, retry, and dead-letter
   replay windows can no longer surface old events.

This ordering matters because retries or retained WAL can deliver an older
payload after the database has already changed.

Renames, removals, type changes, and replica-identity changes are not equivalent
to this additive example. They require an explicit compatibility plan. Re-run
Mammoth validation and startup preflight when publications or replica identity
change.

Backfills are DML rather than DDL: an `UPDATE` backfill on a published table
will produce row-change events and should be capacity-planned accordingly.

## Boundary

Mammoth relays row changes. It does not deliver migrations, negotiate schema
versions, update downstream schemas, or determine whether a receiver is
compatible. Application migrations or infrastructure tooling own PostgreSQL
DDL, and destination teams own compatible consumer deployment.

## Reset

```bash
docker compose down -v
```
