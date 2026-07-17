# PostgreSQL Observability Example

This example runs Mammoth's relay and observability server as separate
processes against the same PostgreSQL slot and SQLite operational state. It
also provides native PostgreSQL catalog queries so operators can correlate
Mammoth's readiness and Prometheus output with the source database.

```text
pg_replication_slots + pg_stat_replication
                    ↓
PostgreSQL → Mammoth relay → webhook receiver
                    ↓
       /healthz + /readyz + /metrics
```

The observability process is read-only with respect to PostgreSQL. It inspects
the slot but does not create, drop, consume, or acknowledge it.

## Run

Start PostgreSQL, the receiver, the relay, and the separate observability
process:

```bash
docker compose up -d --build
```

Wait for Mammoth to create and activate its slot, then inspect readiness:

```bash
curl -i http://localhost:9394/healthz
curl -i http://localhost:9394/readyz
```

Inspect Mammoth's PostgreSQL slot metrics:

```bash
curl -s http://localhost:9394/metrics \
  | grep '^mammoth_postgres_slot_'
```

Correlate those metrics with PostgreSQL's catalogs:

```bash
docker compose run --rm postgres_inspector
```

Produce three changes:

```bash
docker compose run --rm producer
```

Then inspect the receiver, catalogs, readiness, and metrics again:

```bash
docker compose logs webhook_receiver
docker compose run --rm postgres_inspector
curl -s http://localhost:9394/readyz
curl -s http://localhost:9394/metrics
```

Expected healthy signals include:

- `/readyz` returns HTTP 200 with `"status":"ready"`;
- `mammoth_postgres_slot_inspection_up`, `_present`, `_ready`, and `_active`
  report `1`;
- PostgreSQL reports the slot as active with `wal_status` equal to `reserved`;
- `confirmed_flush_lsn` advances after delivery and acknowledgement; and
- the publication catalog contains `public.orders`.

`restart_lsn`, `confirmed_flush_lsn`, retained WAL, and safe WAL size are
positions or snapshots, not throughput rates. Alert on sustained changes and
capacity thresholds rather than one scrape.

## Boundary

Mammoth exposes relay-owned operational state and read-only slot inspection.
PostgreSQL infrastructure monitoring still owns disk capacity, archive health,
WAL generation rate, server configuration, and `catalog_xmin` age. The native
queries in this example illustrate that complementary database-side view.

The separate observability process shares the SQLite volume with the relay, so
it can report checkpoints, delivered-envelope rows, and dead letters. Dispatch
counters remain process-local and are not transferred from the relay process.

## Reset

```bash
docker compose down -v
```
