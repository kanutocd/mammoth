# Adapt Mammoth to an Existing Application

Mammoth does not require an application SDK. Adopting it means giving a separate
Mammoth process read access to selected PostgreSQL changes and pointing it at a
webhook receiver.

## 1. Choose the database boundary

Start with one or two tables whose changes are useful downstream. Every table
publishing `UPDATE` or `DELETE` needs a primary key, an eligible replica identity
index, or `REPLICA IDENTITY FULL`.

Create the publication explicitly:

```sql
CREATE PUBLICATION mammoth_publication
FOR TABLE public.orders, public.customers;
```

Adding a table later is an explicit database migration:

```sql
ALTER PUBLICATION mammoth_publication ADD TABLE public.shipments;
```

Mammoth relays row changes. PostgreSQL logical replication does not emit DDL or
sequence changes.

### Column-level changes and opting out

The quickstart deliberately configures:

```sql
ALTER TABLE public.orders REPLICA IDENTITY FULL;
```

This makes PostgreSQL include complete old and new rows for updates. Mammoth can
then emit accurate column-level differences:

```json
{
  "changes": [
    {
      "name": "status",
      "old_value": "pending",
      "new_value": "paid"
    }
  ]
}
```

`FULL` is useful when receivers need before/after values, but it increases WAL
volume and sends previous values for every column—including columns containing
sensitive data. Evaluate that cost table by table.

To opt out and use the primary key as replica identity:

```sql
ALTER TABLE public.orders REPLICA IDENTITY DEFAULT;
```

The table must have a primary key. Mammoth will continue delivering the new row
under `data`, but `changes` will be an empty array when PostgreSQL does not
provide a complete old row. Receivers must treat that as “column differences
unavailable,” not “the UPDATE changed nothing.”

An eligible unique index can provide a narrower identity boundary:

```sql
ALTER TABLE public.orders
REPLICA IDENTITY USING INDEX orders_external_id_key;
```

This supports identifying rows for updates and deletes but, like `DEFAULT`,
does not provide complete old values for column-level differences.

## 2. Prepare PostgreSQL

The server must have logical replication enabled:

```text
wal_level = logical
max_replication_slots > 0
max_wal_senders > 0
```

Create a dedicated login according to your organization's security policy. A
typical starting point, run by a database administrator, is:

```sql
CREATE ROLE mammoth WITH LOGIN REPLICATION PASSWORD 'replace-me';
GRANT CONNECT ON DATABASE app_production TO mammoth;
GRANT USAGE ON SCHEMA public TO mammoth;
GRANT SELECT ON TABLE public.orders, public.customers TO mammoth;
```

Do not reuse the application's write-capable database role.

## 3. Copy and edit the Mammoth config

Copy [`mammoth/mammoth.yml`](./mammoth/mammoth.yml) and change only these values
for a first integration:

| Setting | Replace with |
|---|---|
| `mammoth.name` | Stable environment-specific name |
| `postgres.*` | Your database host, port, database, and Mammoth user |
| `replication.slot` | A unique, stable slot name |
| `replication.publications` | Publications created by your DBA/migration |
| `webhook.url` | Your receiver's network-reachable URL |
| secret environment variables | Secret-manager supplied values |
| `sqlite.path` | A persistent volume path writable by the non-root image |

Keep `delivery.unit: transaction`, ordered delivery, and concurrency at the
quickstart defaults until receiver idempotency and ordering behavior have been
tested.

Validate before deployment:

```bash
mammoth validate /config/mammoth.yml
mammoth bootstrap /config/mammoth.yml
```

## 4. Add Mammoth beside the application

The essential Compose shape is:

```yaml
services:
  mammoth-init:
    image: ghcr.io/kanutocd/mammoth:v1.2.0
    command: ["sh", "-c", "mammoth validate /config/mammoth.yml && mammoth bootstrap /config/mammoth.yml"]
    environment: &mammoth-environment
      MAMMOTH_POSTGRES_PASSWORD: ${MAMMOTH_POSTGRES_PASSWORD}
      MAMMOTH_WEBHOOK_AUTHORIZATION: ${MAMMOTH_WEBHOOK_AUTHORIZATION}
      MAMMOTH_WEBHOOK_SIGNING_SECRET: ${MAMMOTH_WEBHOOK_SIGNING_SECRET}
    volumes: &mammoth-volumes
      - ./mammoth.yml:/config/mammoth.yml:ro
      - mammoth-data:/app/.sqlite3

  mammoth:
    image: ghcr.io/kanutocd/mammoth:v1.2.0
    command: ["start", "/config/mammoth.yml"]
    environment: *mammoth-environment
    volumes: *mammoth-volumes
    depends_on:
      mammoth-init:
        condition: service_completed_successfully
    restart: unless-stopped

volumes:
  mammoth-data:
```

In Kubernetes, use the Mammoth Helm chart and a persistent volume for the same
SQLite/slot continuity boundary.

## 5. Prove the integration

Before routing production traffic:

1. Insert a uniquely identifiable test row.
2. Confirm the receiver gets an `insert` event.
3. Update that row and confirm the receiver gets an `update` event.
4. Return HTTP 500 temporarily and confirm retries.
5. Restore HTTP 2xx and confirm successful recovery.
6. Restart Mammoth and confirm already delivered work is not applied twice.
7. Exhaust retries in staging, inspect the dead letter, fix the receiver, and
   practice explicit replay.

The included [`scripts/smoke-test.sh`](./scripts/smoke-test.sh) demonstrates the
first five checks.

## Production checklist

- Store PostgreSQL, authorization, and signing secrets outside YAML.
- Use TLS for PostgreSQL and webhook traffic across untrusted networks.
- Verify HMAC signatures against the exact raw request body.
- Reject stale signing timestamps to limit replay.
- Atomically deduplicate receiver side effects by `event_id`.
- Make consumers tolerant of additive payload and database columns.
- Use a permanent, DBA-managed replication slot after bootstrap.
- Back up Mammoth operational state with the slot as one continuity boundary.
- Alert on `/readyz`, pending dead letters, retained WAL, and PostgreSQL disk.
- Set PostgreSQL WAL retention guardrails appropriate to the recovery budget.
- Coordinate schema changes with webhook consumers before changing source rows.
- Document and rehearse dead-letter inspection and replay.

Use the quickstart's [`WAL-RETENTION.md`](./WAL-RETENTION.md) walkthrough to
measure WAL accumulation during graceful and abnormal Mammoth outages and
verify recovery before selecting a production retention limit.

For deeper operational guidance, see
[`../docs/POSTGRESQL.md`](../docs/POSTGRESQL.md),
[`../docs/OBSERVABILITY.md`](../docs/OBSERVABILITY.md), and
[`../docs/TROUBLESHOOTING.md`](../docs/TROUBLESHOOTING.md).
