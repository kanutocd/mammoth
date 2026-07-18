# WAL Retention and Mammoth Outage Testing

Mammoth uses a permanent PostgreSQL logical replication slot. When Mammoth is
unavailable, PostgreSQL retains the WAL required for Mammoth to continue from
its last acknowledged position. This preserves delivery continuity but can fill
the PostgreSQL disk during a long outage.

The quickstart bounds slot-retained WAL with:

```text
max_slot_wal_keep_size=1GB
```

Override the value without editing Compose:

```bash
POSTGRES_MAX_SLOT_WAL_KEEP_SIZE=5GB docker compose up --build --wait
```

Set it to `-1` only when unlimited retention is intentional:

```bash
POSTGRES_MAX_SLOT_WAL_KEEP_SIZE=-1 docker compose up --build --wait
```

PostgreSQL enforces `max_slot_wal_keep_size` at checkpoint time. It is a
last-resort disk guardrail, not an exact cap on the complete `pg_wal`
directory. If required WAL is removed, the slot may become `lost` and Mammoth
cannot safely resume from its durable checkpoint. Recovery then requires
external reconciliation or backfill followed by a new slot/checkpoint
continuity boundary.

See the PostgreSQL 17 documentation for
[`max_slot_wal_keep_size`](https://www.postgresql.org/docs/17/runtime-config-replication.html)
and [`pg_replication_slots`](https://www.postgresql.org/docs/17/view-pg-replication-slots.html).

## What to verify

Test both a graceful Mammoth stop and an abnormal process death:

1. The slot becomes inactive while Mammoth is unavailable.
2. Retained WAL grows while PostgreSQL continues receiving writes.
3. Mammoth reconnects and advances `confirmed_flush_lsn` after a published
   marker event is delivered following a short outage.
4. Retained WAL falls after Mammoth catches up.
5. An outage that exceeds the configured guardrail invalidates continuity
   instead of consuming disk indefinitely.
6. Mammoth fails closed if PostgreSQL has removed WAL required by its
   checkpoint.

Run these tests only against the disposable quickstart database. Do not drop a
production slot or clear production Mammoth operational state.

## 1. Start from a healthy stack

```bash
cd webhooks-quickstart
docker compose up -d --build --wait
docker compose ps
```

Confirm the effective guardrail:

```bash
docker compose exec -T postgres \
  psql -U mammoth -d mammoth_demo \
  -c "SHOW max_slot_wal_keep_size;"
```

Inspect Mammoth's slot:

```bash
docker compose exec -T postgres \
  psql -U mammoth -d mammoth_demo -x -c "
SELECT
  slot_name,
  active,
  active_pid,
  restart_lsn,
  confirmed_flush_lsn,
  pg_current_wal_lsn() AS current_wal_lsn,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
  ) AS retained_wal,
  wal_status,
  pg_size_pretty(safe_wal_size) AS safe_wal,
  inactive_since,
  invalidation_reason
FROM pg_replication_slots
WHERE slot_name = 'mammoth_quickstart';
"
```

On a healthy stack, expect:

- `active` is `t`;
- `wal_status` is `reserved`;
- `invalidation_reason` is empty; and
- retained WAL is relatively small.

Record the physical WAL directory size:

```bash
docker compose exec postgres \
  du -sh /var/lib/postgresql/data/pg_wal
```

The directory size and slot-retained bytes are related but not identical.
PostgreSQL allocates and recycles WAL in segments, and other database activity,
checkpoints, archiving, and `min_wal_size` also affect the directory.

## 2. Create an isolated WAL probe

Create a logged table that is not part of `mammoth_publication`. It generates
WAL without sending thousands of events to the Webhook Event Console:

```bash
docker compose exec -T postgres \
  psql -U mammoth -d mammoth_demo <<'SQL'
CREATE TABLE IF NOT EXISTS wal_retention_probe (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payload text NOT NULL
);
SQL
```

Each probe batch below inserts approximately 50 MB of payload:

```bash
docker compose exec -T postgres \
  psql -U mammoth -d mammoth_demo <<'SQL'
INSERT INTO wal_retention_probe (payload)
SELECT string_agg(md5(g::text || ':' || n::text), '')
FROM generate_series(1, 25000) AS rows(g)
CROSS JOIN LATERAL generate_series(1, 64) AS parts(n)
GROUP BY g;

CHECKPOINT;
SQL
```

WAL volume will not exactly equal row payload size because PostgreSQL also
writes page, index, transaction, and checkpoint records.

### Why catch-up needs a published marker

`wal_retention_probe` is intentionally outside `mammoth_publication`. PostgreSQL
must retain and decode its WAL for the logical slot, but pgoutput filters those
row changes before Mammoth receives them. Mammoth acknowledges WAL only after a
published work item has a durable delivery outcome; reconnecting by itself does
not acknowledge the filtered probe WAL.

After Mammoth reconnects, create one small change on the published `orders`
table:

```bash
docker compose exec -T postgres \
  psql -U mammoth -d mammoth_demo -c "
UPDATE orders
SET updated_at = clock_timestamp()
WHERE id = (SELECT min(id) FROM orders);
"
```

Wait for this marker transaction to appear in the Webhook Event Console before
checking `confirmed_flush_lsn`. Its durable delivery gives Mammoth a safe
acknowledgement boundary beyond the filtered probe WAL. Do not add
`wal_retention_probe` to the publication merely to make this test advance; that
would send thousands of large probe events to the destination.

## 3. Test graceful shutdown and catch-up

Stop only Mammoth:

```bash
docker compose stop mammoth
docker compose ps mammoth
```

Run the slot query from step 1. Expect `active` to be `f` and
`inactive_since` to be populated.

Run one probe batch, then run the slot query and WAL-directory measurement
again. `retained_wal` should increase while Mammoth is stopped.

Restart Mammoth:

```bash
docker compose start mammoth
docker compose ps mammoth
docker compose exec -T mammoth \
  mammoth status /config/mammoth.yml
```

The normal long-running `mammoth start` path may produce no steady-state log
output. An empty `docker compose logs mammoth` result is not by itself a
failure. Confirm that Compose reports Mammoth as healthy and that the slot query
shows `active = t`.

Run the published `orders` marker from step 2 and wait for it to appear in the
Webhook Event Console. Repeat the slot query until:

- `active` returns to `t`;
- `confirmed_flush_lsn` advances;
- retained WAL falls substantially; and
- `wal_status` remains `reserved`.

If `confirmed_flush_lsn` advances but `restart_lsn` or retained WAL lags, run
one checkpoint and query the slot again:

```bash
docker compose exec -T postgres \
  psql -U mammoth -d mammoth_demo \
  -c "CHECKPOINT;"
```

The physical `pg_wal` directory may not shrink immediately because PostgreSQL
normally recycles reusable WAL segments.

## 4. Test abnormal termination and catch-up

Terminate Mammoth without allowing process-level shutdown hooks to run:

```bash
docker compose kill -s SIGKILL mammoth
docker compose ps mammoth
```

If the Compose restart policy immediately starts Mammoth, confirm the abnormal
termination from the container state or recent exit status, then stop it for
the retention test. Mammoth may not emit a normal shutdown or startup log:

```bash
docker compose logs --since=2m mammoth
docker compose stop mammoth
```

Run the slot query and confirm that the slot is inactive. Run another probe
batch and verify that retained WAL grows.

Start Mammoth and inspect recovery:

```bash
docker compose start mammoth
docker compose ps mammoth
docker compose exec -T mammoth \
  mammoth status /config/mammoth.yml
```

After the slot becomes active, run the published `orders` marker from step 2 and
wait for it in the Webhook Event Console. Verify the same catch-up conditions as
the graceful test. This marker is both the post-reconnect delivery check and the
durable boundary that lets Mammoth acknowledge past filtered probe WAL.

## 5. Monitor through Mammoth

The observability service exposes PostgreSQL slot state:

```bash
curl -fsS http://localhost:9393/metrics |
  grep 'mammoth_postgres_slot_'
```

Monitor at least:

```text
mammoth_postgres_slot_active
mammoth_postgres_slot_retained_wal_bytes
mammoth_postgres_slot_safe_wal_size_bytes
mammoth_postgres_slot_wal_status
mammoth_postgres_slot_invalidated
mammoth_postgres_slot_inactive_since_timestamp_seconds
```

Alert when the slot is unexpectedly inactive, retained WAL grows continuously,
`safe_wal_size` approaches zero, `wal_status` is `unreserved` or `lost`, or the
slot is invalidated. Also monitor PostgreSQL filesystem capacity independently;
Mammoth cannot observe the database host's complete disk usage.

## 6. Test the guardrail

The default `1GB` allowance makes accidental invalidation unlikely during the
smaller catch-up tests. To exercise invalidation quickly, recreate the
disposable PostgreSQL service with a smaller allowance:

```bash
POSTGRES_MAX_SLOT_WAL_KEEP_SIZE=64MB \
  docker compose up -d --force-recreate --wait
```

Confirm `SHOW max_slot_wal_keep_size` reports `64MB`, stop Mammoth, and run
enough probe batches to exceed the allowance. Each batch ends with an explicit
checkpoint, where PostgreSQL evaluates the limit.

Inspect the slot after every batch. Depending on checkpoint and WAL-segment
boundaries, it may progress from `reserved` or `extended` to `unreserved` and
eventually `lost`. Stop generating data once `wal_status` is `lost` or
`invalidation_reason` is populated.

Start Mammoth:

```bash
docker compose start mammoth
docker compose logs --since=2m mammoth
docker compose ps mammoth
```

Expected behavior is a fail-closed startup or replication failure explaining
that the configured slot can no longer satisfy the durable checkpoint. Mammoth
must not silently create a replacement slot and present it as continuous
delivery. Because normal steady-state logging can be empty, also use the
container state, `mammoth status`, readiness endpoint, and slot query when
confirming the failure.

For this disposable quickstart, reset all state after the invalidation test:

```bash
docker compose down -v
docker compose up -d --build --wait
```

Do not use that reset procedure in production. Production recovery requires
determining the missing WAL interval, backfilling or reconciling affected
records, and deliberately establishing fresh Mammoth operational state and a
new replication-slot boundary.

## 7. Clean up after non-invalidating tests

While Mammoth is running:

```bash
docker compose exec -T postgres \
  psql -U mammoth -d mammoth_demo \
  -c "DROP TABLE IF EXISTS wal_retention_probe;"

docker compose exec -T postgres \
  psql -U mammoth -d mammoth_demo \
  -c "
UPDATE orders
SET updated_at = clock_timestamp()
WHERE id = (SELECT min(id) FROM orders);
"
```

Wait for the published cleanup marker to reach the Webhook Event Console, then
run `CHECKPOINT;` and verify that retained WAL is small:

```bash
docker compose exec -T postgres \
  psql -U mammoth -d mammoth_demo \
  -c "CHECKPOINT;"
```

Do not run `docker compose down -v` unless deleting all quickstart PostgreSQL,
Mammoth, and Event Console state is intentional.

## Choosing a production allowance

Estimate:

```text
required allowance =
  peak WAL generation rate × maximum recoverable outage × safety margin
```

Then constrain that estimate by available PostgreSQL disk and the time Mammoth
needs to decode and deliver the backlog. A larger allowance protects longer
delivery continuity but permits more disk consumption. A smaller allowance
protects disk sooner but shortens the outage window before reconciliation is
required.

The quickstart's `1GB` value is a developer-machine default, not a production
recommendation. Measure the application's WAL rate and rehearse both catch-up
and invalidation recovery before choosing a production value.
