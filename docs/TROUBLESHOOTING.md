# Troubleshooting

This guide records common issues encountered while running Mammoth locally, with Docker Compose, or with Kubernetes.

## `secret "postgres-secrets" not found`

Symptom:

```text
CreateContainerConfigError
Error: secret "postgres-secrets" not found
```

Cause:

The Helm chart references a PostgreSQL password Secret that does not exist.

Fix:

```bash
kubectl create secret generic postgres-secrets \
  --from-literal=password=postgres

kubectl rollout restart deploy/mammoth
```

If your chart values use a different secret name or key, inspect:

```bash
helm get values mammoth --all
helm get manifest mammoth | grep -A5 -B5 postgres-secrets
```

## `could not translate host name "postgres-service.internal"`

Symptom:

```text
PostgreSQL CDC source failed: could not translate host name "postgres-service.internal" to address: Name or service not known
```

Cause:

The default Postgres host is not resolvable inside your Kubernetes cluster.

Fix:

Point Mammoth to a real Kubernetes Service:

```bash
helm upgrade mammoth ./charts/mammoth \
  --set postgres.host=postgres-service \
  --set postgres.port=5432
```

## Mammoth pod is running but no webhook arrives

Possible causes:

- no publication exists
- the table is not part of the publication
- webhook URL is not reachable from inside the cluster
- Mammoth started before the publication was created and needs a restart
- destination returns an error and the event is dead-lettered

Check publications:

```bash
kubectl exec deploy/postgres -- psql -U postgres -d mammoth_demo -c "SELECT * FROM pg_publication;"
```

Create a table and publication:

```bash
kubectl exec deploy/postgres -- psql -U postgres -d mammoth_demo -c \
"CREATE TABLE IF NOT EXISTS orders (id bigserial PRIMARY KEY, status text NOT NULL, total_cents integer NOT NULL);"

kubectl exec deploy/postgres -- psql -U postgres -d mammoth_demo -c \
"CREATE PUBLICATION mammoth_publication FOR TABLE orders;"
```

Restart Mammoth and insert a row:

```bash
kubectl rollout restart deploy/mammoth
kubectl exec deploy/postgres -- psql -U postgres -d mammoth_demo -c \
"INSERT INTO orders (status, total_cents) VALUES ('created', 8888);"
```

## Replica identity preflight fails

Mammoth lists every published `UPDATE`/`DELETE` table without usable old-row
identity. Inspect the configured publications and table identity:

```sql
SELECT
  publication.pubname,
  publication.pubupdate,
  publication.pubdelete,
  publication_table.schemaname,
  publication_table.tablename,
  relation.relreplident
FROM pg_publication_tables AS publication_table
JOIN pg_publication AS publication USING (pubname)
JOIN pg_namespace AS namespace
  ON namespace.nspname = publication_table.schemaname
JOIN pg_class AS relation
  ON relation.relnamespace = namespace.oid
 AND relation.relname = publication_table.tablename
WHERE publication.pubname = 'mammoth_publication';
```

Add a primary key, select an eligible unique index with `REPLICA IDENTITY USING
INDEX`, use `REPLICA IDENTITY FULL`, or remove `UPDATE`/`DELETE` from the
publication when it is intentionally insert-only. `FULL` is valid but has WAL
volume and row-matching costs.

## Replication slot is active but nothing is delivered

Check slot movement:

```sql
SELECT
  slot_name,
  active,
  restart_lsn,
  confirmed_flush_lsn
FROM pg_replication_slots;
```

If `confirmed_flush_lsn` moves, Mammoth is consuming the stream. The issue is likely downstream delivery configuration.

Check webhook URL and Mammoth logs:

```bash
kubectl logs deploy/mammoth --tail=200
helm get values mammoth --all
```

## PostgreSQL slot preflight fails

Mammoth fails closed when the configured slot is missing, active elsewhere,
lost, invalidated, incompatible, or unable to serve the durable checkpoint.
Inspect the complete slot state:

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
WHERE slot_name = 'mammoth_prod';
```

The available columns vary by PostgreSQL version. Remove fields that the
running server does not expose.

Do not solve a missing or invalidated slot by recreating it while retaining
Mammoth's old checkpoint. The lost interval requires external backfill or
reconciliation. After that process, establish new safe operational state and
restart Mammoth. For a first-time deployment with no checkpoint,
`auto_create_slot: true` may create the missing slot.

The same state is available through `/readyz` and the
`mammoth_postgres_slot_*` Prometheus gauges. If
`mammoth_postgres_slot_inspection_up` is `0`, check PostgreSQL connectivity and
catalog permissions. If retained WAL grows continuously, investigate stalled
delivery or acknowledgement before PostgreSQL storage is exhausted.

## Retained WAL keeps growing

Check Mammoth readiness, pending dead letters, destination latency, and the gap
between `restart_lsn` and `confirmed_flush_lsn`. A slow or failing destination
can hold the contiguous watermark behind later completed work.

Alert before retained WAL reaches the environment's disk or recovery budget.
`max_slot_wal_keep_size` and, where supported,
`idle_replication_slot_timeout` can protect PostgreSQL, but crossing those
guardrails may invalidate the slot. Increasing a guardrail buys investigation
time; it does not repair stalled delivery or acknowledgement. Disk-capacity and
`catalog_xmin` age monitoring belong in the PostgreSQL infrastructure stack.

## Webhook payloads changed after a schema migration

PostgreSQL logical replication does not deliver DDL. Mammoth may receive new
relation metadata and emit a changed row shape, but it does not migrate or
version webhook consumers.

Deploy consumers that accept both shapes before applying additive database
changes. For renames, removals, type changes, or replica-identity changes,
coordinate a compatibility window and re-run Mammoth startup preflight. If a
consumer rejects the new shape, correct the consumer or routing policy before
replaying the resulting dead letters.

## Sequence values diverge in a downstream database

Logical replication delivers generated values stored in rows but does not copy
the sequence's current state. Webhook consumers normally need no action. A
downstream database intended to become writable must synchronize sequences
separately before cutover.

## A destination reports a duplicate-key or semantic conflict

Mammoth is not a PostgreSQL subscriber applying SQL, so PostgreSQL subscription
conflict-repair procedures do not apply. Destinations must use Mammoth
idempotency keys and their own conflict policy. Mammoth retries delivery and
dead-letters exhausted failures; after fixing the destination condition, replay
the affected dead letter explicitly.

## Docker Compose example shows duplicate dead-letter rows

Cause:

The Docker volume was reused across multiple runs with the same sample `event_id`.

Fix:

Reset the example volume:

```bash
docker compose down -v
```

Then rerun the example.

## `sqlite3` is not available in the container

The runtime image may not include `sqlite3`. Keep the runtime image lean and inspect the database with a temporary helper container.

Example:

```bash
docker run --rm -it \
  -v failing_webhook_retry_mammoth_retry_data:/data \
  alpine:3.20 \
  sh -c "apk add --no-cache sqlite && sqlite3 /data/mammoth.db '.tables'"
```

## zsh asks to correct `exec` to `exe`

When running commands like:

```bash
kubectl exec deploy/postgres -- psql -U postgres -d mammoth_demo -c "SELECT 1;"
```

zsh may ask:

```text
zsh: correct 'exec' to 'exe' [nyae]?
```

Answer `n` or disable correction for the command. The `kubectl exec` command is correct.
