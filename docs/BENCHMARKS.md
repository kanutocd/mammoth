<!--
# @title Benchmarks
-->
# Benchmarks

Mammoth benchmarks are small, repeatable scripts for validating showcase
features and helping operators tune configuration knobs.

The benchmarks are intentionally local. They do not require PostgreSQL unless a
future benchmark says so explicitly.

The benchmark scripts live in:

```text
benchmark/
```

The detailed source README is [`benchmark/README.md`](https://github.com/kanutocd/mammoth/blob/main/benchmark/README.md).
This page mirrors that benchmark map so the docs site and repository benchmark
entrypoint stay aligned.

## Benchmark Map

| Script | Product surface | Primary config knobs |
| --- | --- | --- |
| `benchmark/serialization.rb` | event and transaction payload projection | fallback-ID usage, events per transaction |
| `benchmark/payload_policy.rb` | deterministic destination payload projection | policy action, events per transaction, selected columns |
| `benchmark/concurrent_delivery.rb` | `cdc-concurrent` downstream runtime | `runtime.concurrency`, `runtime.preserve_order` |
| `benchmark/webhook_delivery.rb` | real `WebhookSink` HTTP delivery | `webhook.timeout_seconds`, `webhook.headers`, `webhook.header_env`, `webhook.signing`, `delivery.unit` |
| `benchmark/webhook_fanout.rb` | multi-destination webhook fanout | `destinations`, destination count, destination `timeout_seconds`, `route`, destination `retry`, `delivery.unit` |
| `benchmark/sqlite_operational_state.rb` | SQLite operational state | SQLite volume performance, checkpoint cadence, ledger/DLQ size |
| `benchmark/observability_snapshot.rb` | `/readyz` and `/metrics` snapshot cost | SQLite size, scrape frequency |
| `benchmark/dlq_replay.rb` | dead-letter replay | DLQ size, fanout destination count, `delivery.unit` |

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
commit SHA. Do not commit `benchmark/results/`; it is ignored by git.

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
inactive, matching `remove`, and matching `mask` scenarios. Canonical
serialization happens before the timed region, so results isolate deterministic
destination projection, JSON-compatible copy cost, selector evaluation,
redaction, and policy-fingerprint metadata.

The benchmark excludes PostgreSQL decoding, routing, HTTP, HMAC signing,
retries, and operational-state persistence.

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
by `pgoutput-source-adapter`; source transaction buffering and PostgreSQL
slot/checkpoint continuity preflight are outside this downstream runtime
benchmark.
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

## Existing Snapshot

The tables below are retained from an earlier run of
`benchmark/concurrent_delivery.rb`. Do not treat them as universal performance
claims. Re-run benchmarks on your own hardware and publish the exact command,
environment, and Mammoth commit SHA with any interpretation.

### Benchmark Configuration

* 10,000 transactions
* 4 events per transaction
* 40,000 total events
* `preserve_order: false`

### Fast Sink (10ms)

| Concurrency | Transactions/sec | Events/sec | Avg Latency (ms) | P95 Latency (ms) | Elapsed (s) |
| ----------- | ---------------: | ---------: | ---------------: | ---------------: | ----------: |
| 1           |            96.50 |     385.98 |           10.204 |           10.404 |     103.631 |
| 5           |           482.26 |    1929.04 |           10.235 |           10.451 |      20.736 |
| 10          |           955.04 |    3820.17 |           10.287 |           11.047 |      10.471 |
| 25          |          2419.65 |    9678.61 |           10.173 |           10.330 |       4.133 |

### Realistic Webhook (50ms)

| Concurrency | Transactions/sec | Events/sec | Avg Latency (ms) | P95 Latency (ms) | Elapsed (s) |
| ----------- | ---------------: | ---------: | ---------------: | ---------------: | ----------: |
| 1           |            19.85 |      79.40 |           50.206 |           50.405 |     503.795 |
| 5           |            99.27 |     397.07 |           50.234 |           50.419 |     100.737 |
| 10          |           198.40 |     793.61 |           50.181 |           50.402 |      50.403 |
| 25          |           495.11 |    1980.44 |           50.224 |           50.420 |      20.198 |
