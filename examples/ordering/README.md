# Ordering Example

This example demonstrates Mammoth's `runtime.preserve_order` tradeoff for
transaction-level webhook delivery.

It produces three PostgreSQL transactions in commit order:

```text
A
B
C
```

The webhook receiver intentionally makes transaction `A` slow and transactions
`B` and `C` fast.

```text
A -> 1.0s delivery latency
B -> 0.1s delivery latency
C -> 0.1s delivery latency
```

This makes the ordering behavior visible in the receiver logs.

## preserve_order: true

Run with the default config:

```bash
docker compose down -v
docker compose build --no-cache mammoth
docker compose up --force-recreate
```

Expected completion order:

```text
A
B
C
```

Even though `A` is slow, Mammoth preserves transaction delivery order.

Configuration:

```yaml
runtime:
  adapter: concurrent
  concurrency: 25
  preserve_order: true
```

## preserve_order: false

Run with the unordered config:

```bash
docker compose down -v
MAMMOTH_ORDERING_CONFIG=./config/preserve_order_false.yml \
  docker compose up --force-recreate --build
```

Expected completion order is not guaranteed. Because `A` is intentionally slow,
you should usually see `B` and `C` complete before `A`:

```text
B
C
A
```

or:

```text
C
B
A
```

Configuration:

```yaml
runtime:
  adapter: concurrent
  concurrency: 25
  preserve_order: false
```

## What This Proves

`preserve_order: true` favors correctness and deterministic delivery order.

`preserve_order: false` favors maximum downstream throughput when the sink does
not require strict delivery ordering.

Both modes use one PostgreSQL logical replication stream. The difference is how
Mammoth schedules downstream delivery work through `cdc-concurrent`.


## Why `batch_size` is configured

The unordered configuration sets:

```yaml
runtime:
  concurrency: 25
  batch_size: 3
  preserve_order: false
```

The batch size lets Mammoth submit transactions A, B, and C to the concurrent
runtime together. Because A is intentionally slower than B and C, unordered
delivery can visibly complete B/C before A.
