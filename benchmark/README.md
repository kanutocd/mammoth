# Mammoth Benchmarks

This directory contains small, repeatable benchmarks for validating Mammoth's
showcase features and helping operators tune configuration knobs.

The benchmarks are intentionally local. They do not require PostgreSQL unless a
future benchmark says so explicitly.

## Benchmark Map

| Script | Product surface | Primary config knobs |
| --- | --- | --- |
| `serialization.rb` | event and transaction payload projection | fallback-ID usage, events per transaction |
| `payload_policy.rb` | deterministic destination payload projection | policy action, events per transaction, selected columns |
| `concurrent_delivery.rb` | `cdc-concurrent` downstream runtime | `runtime.concurrency`, `runtime.preserve_order` |
| `webhook_delivery.rb` | real `WebhookSink` HTTP delivery | `webhook.timeout_seconds`, `webhook.headers`, `webhook.header_env`, `webhook.signing`, `delivery.unit` |
| `webhook_fanout.rb` | multi-destination webhook fanout | `destinations`, destination count, destination `timeout_seconds`, `route`, destination `retry`, `delivery.unit` |
| `sqlite_operational_state.rb` | SQLite operational state | SQLite volume performance, checkpoint cadence, ledger/DLQ size |
| `observability_snapshot.rb` | `/readyz` and `/metrics` snapshot cost | SQLite size, scrape frequency |
| `dlq_replay.rb` | dead-letter replay | DLQ size, fanout destination count, `delivery.unit` |

Set `MAMMOTH_BENCH_JSON=1` on any benchmark to emit machine-readable JSON after
the table.

Benchmarks that construct a real `DeliveryWorker` inject stores from one
configured `OperationalState::SQLiteAdapter`. The worker records delivered
ledger and dead-letter outcomes; it does not advance checkpoints independently.
These local downstream benchmarks do not measure the shared contiguous progress
coordinator or PostgreSQL acknowledgement.

## Snapshot Runner

Run all benchmarks and write publishable artifacts:

```bash
bundle exec ruby benchmark/snapshot.rb
```

The runner writes:

```text
benchmark/results/<timestamp>/snapshot.md
benchmark/results/<timestamp>/snapshot.json
benchmark/results/<timestamp>/*-trial-*.out
benchmark/results/<timestamp>/*-trial-*.err
```

Use smoke mode for quick validation:

```bash
MAMMOTH_SNAPSHOT_PRESET=smoke bundle exec ruby benchmark/snapshot.rb
```

Run selected benchmarks:

```bash
MAMMOTH_SNAPSHOT_BENCHMARKS=concurrent_delivery,webhook_fanout \
bundle exec ruby benchmark/snapshot.rb
```

Run multiple trials:

```bash
MAMMOTH_SNAPSHOT_TRIALS=3 bundle exec ruby benchmark/snapshot.rb
```

Override normal benchmark knobs the same way you would when running a benchmark
directly:

```bash
MAMMOTH_BENCH_CONCURRENCY=1,5,10,25,50 \
MAMMOTH_BENCH_LATENCY_MS=25 \
bundle exec ruby benchmark/snapshot.rb
```

Publish snapshots with the generated command, environment metadata, and Mammoth
commit SHA. Routine `benchmark/results/` runs are ignored. Intentionally
selected references may be unignored with their generated Markdown, JSON, and
successful raw output as described in `benchmark/results/README.md`.

## Serialization

```bash
bundle exec ruby benchmark/serialization.rb
```

Measures `Mammoth::EventSerializer` and
`Mammoth::TransactionEnvelopeSerializer` payload projection for four scenarios:

- event payload with an explicit metadata event ID;
- event payload with a deterministic fallback ID;
- transaction payload with explicit envelope and child IDs; and
- transaction payload with deterministic envelope and child fallback IDs.

The benchmark uses identical update values within each transaction and stable
transaction-local sequence numbers. Before timing, it verifies that the
fallback child IDs are unique. Input objects are prebuilt so the results isolate
payload projection, column-change normalization, and fallback digest cost.
JSON encoding, HTTP delivery, source normalization, and persistence are outside
the timed region.

Options:

```bash
MAMMOTH_BENCH_SERIALIZATIONS=100000 \
MAMMOTH_BENCH_WARMUP_SERIALIZATIONS=5000 \
MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 \
bundle exec ruby benchmark/serialization.rb
```

Results include operations and events per second, microseconds and allocations
per operation, and representative payload size. Compare scenarios from the same
run and host; these are local measurements, not universal performance claims.

## Payload Policy

```bash
bundle exec ruby benchmark/payload_policy.rb
```

Measures `Mammoth::PayloadPolicy` against one canonical transaction payload for
three scenarios:

- inactive policy;
- matching `remove` rules; and
- matching `mask` rules.

Canonical serialization happens before the timed region. The benchmark
therefore isolates deterministic destination projection, JSON-compatible copy
cost, selector evaluation, redaction, and policy-fingerprint metadata. It does
not measure PostgreSQL decoding, routing, HTTP, HMAC signing, retries, or
operational-state persistence.

Options:

```bash
MAMMOTH_BENCH_TRANSFORMATIONS=100000 \
MAMMOTH_BENCH_WARMUP_TRANSFORMATIONS=5000 \
MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 \
bundle exec ruby benchmark/payload_policy.rb
```

Results include transformations and events per second, microseconds and
allocations per transformation, and projected payload size.

## Concurrent Delivery

```bash
bundle exec ruby benchmark/concurrent_delivery.rb
```

Measures Mammoth's downstream runtime boundary:

```text
TransactionEnvelope
      ↓
Mammoth::ConcurrentDeliveryRuntime
      ↓
Mammoth::DeliveryProcessor
      ↓
synthetic delivery worker
      ↓
CDC::Core::ProcessorResult + observer notification
```

The benchmark generates exact `CDC::Core::ChangeEvent` and
`CDC::Core::TransactionEnvelope` objects representing work already normalized
by `pgoutput-source-adapter`. It intentionally excludes PostgreSQL transport,
slot/checkpoint continuity preflight, decoding, and transaction buffering.
The runtime uses the core processor/result and observer contracts; its default
no-op observer keeps this benchmark focused on scheduling and delivery cost.
It intentionally omits the progress coordinator, checkpoint writes, and
PostgreSQL acknowledgement.

Useful for tuning:

- `runtime.concurrency`
- `runtime.preserve_order`

Options:

```bash
MAMMOTH_BENCH_TRANSACTIONS=5000 \
MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 \
MAMMOTH_BENCH_LATENCY_MS=25 \
MAMMOTH_BENCH_CONCURRENCY=1,5,10,25,50 \
MAMMOTH_BENCH_PRESERVE_ORDER=false \
bundle exec ruby benchmark/concurrent_delivery.rb
```

This benchmark uses one synthetic destination. It does not measure
multi-destination webhook fanout, per-destination retry behavior, or
per-destination dead-letter behavior.

## Webhook Delivery

```bash
bundle exec ruby benchmark/webhook_delivery.rb
```

Measures real local HTTP delivery through `Mammoth::WebhookSink`.

Useful for tuning:

- `webhook.timeout_seconds`
- static headers
- `webhook.header_env`
- `webhook.signing`
- `delivery.unit`

Options:

```bash
MAMMOTH_BENCH_REQUESTS=1000 \
MAMMOTH_BENCH_DELIVERY_UNIT=transaction \
MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 \
MAMMOTH_BENCH_LATENCY_MS=10 \
MAMMOTH_BENCH_AUTH=true \
MAMMOTH_BENCH_SIGNING=true \
bundle exec ruby benchmark/webhook_delivery.rb
```

## Webhook Fanout

```bash
bundle exec ruby benchmark/webhook_fanout.rb
```

Measures multi-destination webhook fanout using real local HTTP receivers.

Useful for tuning:

- number of `destinations`
- destination `timeout_seconds`
- route selectivity, when compared with expected destination count
- destination-specific retry/backoff policy planning
- `delivery.unit`
- `runtime.concurrency` planning, when compared with `concurrent_delivery.rb`

Options:

```bash
MAMMOTH_BENCH_TRANSACTIONS=250 \
MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 \
MAMMOTH_BENCH_DESTINATIONS=1,2,5,10 \
MAMMOTH_BENCH_LATENCY_MS=10 \
bundle exec ruby benchmark/webhook_fanout.rb
```

## SQLite Operational State

```bash
bundle exec ruby benchmark/sqlite_operational_state.rb
```

Measures local SQLite costs for delivered ledgers, duplicate checks,
checkpoints, and dead-letter writes.

This is intentionally a concrete store microbenchmark: it creates no
`DeliveryWorker` or operator command and measures the built-in SQLite store
implementations directly. Its configured checkpoint interval is synthetic and
does not model Mammoth's contiguous delivery watermark policy.

Useful for tuning:

- SQLite volume class and filesystem
- checkpoint cadence assumptions
- expected delivered ledger size
- expected DLQ size

Options:

```bash
MAMMOTH_BENCH_RECORDS=10000 \
MAMMOTH_BENCH_DEAD_LETTERS=1000 \
MAMMOTH_BENCH_CHECKPOINT_INTERVAL=100 \
bundle exec ruby benchmark/sqlite_operational_state.rb
```

## Observability Snapshot

```bash
bundle exec ruby benchmark/observability_snapshot.rb
```

Measures readiness and Prometheus metrics snapshot cost through a seeded
`OperationalState::SQLiteAdapter` plus representative canonical dispatch
counter series. It intentionally omits a live PostgreSQL slot provider, so
catalog connection latency is outside this local snapshot benchmark.

Useful for tuning:

- metrics scrape frequency
- expected delivered ledger size
- expected DLQ size
- SQLite volume choice

Options:

```bash
MAMMOTH_BENCH_DELIVERED=10000 \
MAMMOTH_BENCH_DEAD_LETTERS=1000 \
MAMMOTH_BENCH_SNAPSHOTS=100 \
bundle exec ruby benchmark/observability_snapshot.rb
```

## DLQ Replay

```bash
bundle exec ruby benchmark/dlq_replay.rb
```

Measures replay mechanics without network IO: pending-row reads, JSON parsing,
exact prepared-payload delivery, targeted fanout replay, delivered-ledger
writes, and row resolution. Seeded rows already contain policy-projected
payloads; policy execution and CDC-core reconstruction are outside the timed
region because production replay does neither.

Useful for tuning:

- DLQ replay batch expectations
- fanout destination count
- `delivery.unit`
- SQLite volume choice

Options:

```bash
MAMMOTH_BENCH_DEAD_LETTERS=1000 \
MAMMOTH_BENCH_DESTINATIONS=2 \
MAMMOTH_BENCH_DELIVERY_UNIT=transaction \
MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 \
bundle exec ruby benchmark/dlq_replay.rb
```

## Reference Snapshot: 2026-07-24

The current reference is a clean, full-preset, single-trial run at commit
`b6889c0` using Ruby 4.0.5 on x86-64 Linux. The
[generated report](results/20260724T104950Z/snapshot.md),
[machine-readable snapshot](results/20260724T104950Z/snapshot.json), and raw
standard output are retained under `benchmark/results/20260724T104950Z/`.

These measurements characterize this host and configuration only. A single
trial is useful as a baseline, not as a statistical confidence interval or
capacity commitment.

### Projection costs

| Scenario | Rate | Time | Allocations |
| --- | ---: | ---: | ---: |
| Event serialization, explicit ID | 56,265 events/sec | 17.773 µs/event | 30/event |
| Event serialization, fallback ID | 31,984 events/sec | 31.266 µs/event | 42/event |
| Transaction serialization, explicit IDs | 55,612 events/sec | 71.927 µs/transaction | 125/transaction |
| Transaction serialization, fallback IDs | 29,188 events/sec | 137.042 µs/transaction | 180/transaction |
| Inactive payload policy | 3,290,989 transformations/sec | 0.304 µs/transformation | 1/transformation |
| Remove payload policy | 14,606 transformations/sec | 68.466 µs/transformation | 154/transformation |
| Mask payload policy | 18,101 transformations/sec | 55.246 µs/transformation | 154/transformation |

Deterministic fallback IDs cost about 1.76 times the explicit-ID event time and
1.91 times the explicit-ID transaction time in this isolated projection test.
Prefer stable upstream IDs when available, while retaining fallback IDs for
correct replay identity. The inactive policy path is effectively a guard
check. Matching remove and mask policies remain CPU-local, but their copy,
selector, and redaction work should be included in CPU planning for very high
event rates.

### Concurrent delivery

The synthetic sink slept for 25 ms per transaction with four events per
transaction and `preserve_order: false`.

| Concurrency | Transactions/sec | Events/sec | Average latency | P95 latency |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 39.36 | 157.45 | 25.262 ms | 25.913 ms |
| 5 | 195.53 | 782.10 | 25.443 ms | 26.694 ms |
| 10 | 382.93 | 1,531.71 | 25.860 ms | 27.513 ms |
| 25 | 956.30 | 3,825.21 | 25.670 ms | 27.540 ms |
| 50 | 1,861.65 | 7,446.58 | 26.013 ms | 28.402 ms |

Throughput scaled to 47.3 times the single-worker rate at concurrency 50, or
about 94.6% of ideal linear scaling, while p95 processing latency increased by
2.489 ms. This indicates that the tested range remained destination-latency
bound. It does not establish that PostgreSQL ingestion, checkpointing, a real
receiver, or a constrained production host will scale identically.

### Delivery, state, and operations

| Surface | Configuration | Result |
| --- | --- | ---: |
| Signed/authenticated webhook | 10 ms receiver latency, 1,000 transactions | 83.53 requests/sec |
| Fanout | 1 destination, 250 transactions | 76.76 requests/sec |
| Fanout | 10 destinations, 2,500 requests | 74.36 requests/sec |
| Delivered-ledger writes | 10,000 rows | 1,630.38 writes/sec |
| Duplicate checks | 10,000 rows | 12,385.59 checks/sec |
| Dead-letter writes | 1,000 rows | 1,654.41 writes/sec |
| Readiness snapshot | 10,000 delivered, 1,000 dead letters | 10,381.57 snapshots/sec |
| Metrics snapshot | 10,000 delivered, 1,000 dead letters | 746.64 snapshots/sec |
| DLQ replay | 1,000 rows, 2 destinations, no network | 1,030.30 rows/sec |

The 10 ms webhook test reached 83.5% of the latency-only ceiling of 100
requests/sec, with the remaining time covering local HTTP, serialization,
authentication, and signing. Fanout held roughly 70–77 requests/sec as
destination count increased, so transaction throughput fell approximately
inversely with the number of destinations; concurrency and route selectivity
are therefore the relevant compensating controls.

SQLite duplicate reads were much faster than ledger and dead-letter writes on
this filesystem. Metrics generation took about 1.34 ms per snapshot and
readiness about 0.096 ms, leaving substantial local headroom at ordinary scrape
intervals. DLQ replay resolved all 1,000 rows with none pending, but its rate
excludes receiver latency, retries, and policy execution.

### Interpretation boundaries

- The snapshot used one trial; repeat trials before treating small differences
  as regressions.
- HTTP receivers and synthetic sinks ran locally, without production network
  variance or rate limits.
- PostgreSQL decoding, WAL transport, acknowledgement, and the contiguous
  progress coordinator are outside these downstream benchmarks.
- SQLite results depend strongly on filesystem, volume, cache, and durability
  behavior.
- Capacity planning should rerun the same commands on deployment-equivalent
  hardware with realistic latency, fanout, payload size, and concurrency.
