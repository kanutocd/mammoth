# Mammoth Benchmark Snapshot

- Generated at: 2026-07-24T10:49:50Z
- Preset: full
- Trials: 1
- Git SHA: b6889c0f37a19c7d1950c28d5524c2742c5feddb
- Ruby: ruby 4.0.5 (2026-05-20 revision 64336ffd0e) +PRISM [x86_64-linux]
- Platform: x86_64-linux
- Host: redacted

These are local benchmark snapshots, not universal performance claims.
Publish the command, environment, and Mammoth commit SHA with any interpretation.

## serialization

Command:

```bash
MAMMOTH_BENCH_SERIALIZATIONS=100000 MAMMOTH_BENCH_WARMUP_SERIALIZATIONS=5000 MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 bundle exec ruby benchmark/serialization.rb
```

### Trial 1

- Status: 0
- Output: `serialization-trial-1.out`

| scenario | operations | events | elapsed_seconds | operations_per_second | events_per_second | microseconds_per_operation | allocations_per_operation | payload_bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| "event_explicit_id" | 100000 | 100000 | 1.7773 | 56265.11 | 56265.11 | 17.773 | 30.0 | 418 |
| "event_fallback_id" | 100000 | 100000 | 3.126555 | 31984.09 | 31984.09 | 31.266 | 42.0 | 438 |
| "transaction_explicit_ids" | 100000 | 400000 | 7.192653 | 13903.08 | 55612.3 | 71.927 | 125.0 | 1960 |
| "transaction_fallback_ids" | 100000 | 400000 | 13.704164 | 7297.05 | 29188.21 | 137.042 | 180.0 | 2052 |

## payload_policy

Command:

```bash
MAMMOTH_BENCH_TRANSFORMATIONS=100000 MAMMOTH_BENCH_WARMUP_TRANSFORMATIONS=5000 MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 bundle exec ruby benchmark/payload_policy.rb
```

### Trial 1

- Status: 0
- Output: `payload_policy-trial-1.out`

| scenario | transformations | events | elapsed_seconds | transformations_per_second | events_per_second | microseconds_per_transformation | allocations_per_transformation | payload_bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| "inactive" | 100000 | 400000 | 0.030386 | 3290988.62 | 13163954.49 | 0.304 | 1.0 | 2549 |
| "remove" | 100000 | 400000 | 6.846577 | 14605.84 | 58423.35 | 68.466 | 154.0 | 1884 |
| "mask" | 100000 | 400000 | 5.524649 | 18100.7 | 72402.79 | 55.246 | 154.0 | 2620 |

## concurrent_delivery

Command:

```bash
MAMMOTH_BENCH_TRANSACTIONS=5000 MAMMOTH_BENCH_WARMUP_TRANSACTIONS=100 MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 MAMMOTH_BENCH_LATENCY_MS=25 MAMMOTH_BENCH_CONCURRENCY=1,5,10,25,50 MAMMOTH_BENCH_PRESERVE_ORDER=false bundle exec ruby benchmark/concurrent_delivery.rb
```

### Trial 1

- Status: 0
- Output: `concurrent_delivery-trial-1.out`

| concurrency | preserve_order | transactions | events | sink_latency_ms | elapsed_seconds | transactions_per_second | events_per_second | average_latency_ms | p95_latency_ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | false | 5000 | 20000 | 25.0 | 127.022683 | 39.36 | 157.45 | 25.262 | 25.913 |
| 5 | false | 5000 | 20000 | 25.0 | 25.57215 | 195.53 | 782.1 | 25.443 | 26.694 |
| 10 | false | 5000 | 20000 | 25.0 | 13.05726 | 382.93 | 1531.71 | 25.86 | 27.513 |
| 25 | false | 5000 | 20000 | 25.0 | 5.228474 | 956.3 | 3825.21 | 25.67 | 27.54 |
| 50 | false | 5000 | 20000 | 25.0 | 2.685796 | 1861.65 | 7446.58 | 26.013 | 28.402 |

## webhook_delivery

Command:

```bash
MAMMOTH_BENCH_REQUESTS=1000 MAMMOTH_BENCH_LATENCY_MS=10 MAMMOTH_BENCH_DELIVERY_UNIT=transaction MAMMOTH_BENCH_AUTH=true MAMMOTH_BENCH_SIGNING=true bundle exec ruby benchmark/webhook_delivery.rb
```

### Trial 1

- Status: 0
- Output: `webhook_delivery-trial-1.out`

| requests | delivery_unit | receiver_latency_ms | auth | signing | received_requests | received_bytes | elapsed_seconds | requests_per_second |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1000 | "transaction" | 10.0 | true | true | 1000 | 1685037 | 11.971409 | 83.53 |

## webhook_fanout

Command:

```bash
MAMMOTH_BENCH_TRANSACTIONS=250 MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 MAMMOTH_BENCH_DESTINATIONS=1,2,5,10 MAMMOTH_BENCH_LATENCY_MS=10 bundle exec ruby benchmark/webhook_fanout.rb
```

### Trial 1

- Status: 0
- Output: `webhook_fanout-trial-1.out`

| destinations | transactions | events | webhook_requests | delivered_envelopes | dead_letters | receiver_latency_ms | elapsed_seconds | transactions_per_second | webhook_requests_per_second | bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 250 | 1000 | 250 | 250 | 0 | 10.0 | 3.257036 | 76.76 | 76.76 | 420528 |
| 2 | 250 | 1000 | 500 | 500 | 0 | 10.0 | 7.124013 | 35.09 | 70.19 | 841056 |
| 5 | 250 | 1000 | 1250 | 1250 | 0 | 10.0 | 17.797789 | 14.05 | 70.23 | 2102640 |
| 10 | 250 | 1000 | 2500 | 2500 | 0 | 10.0 | 33.618806 | 7.44 | 74.36 | 4205280 |

## sqlite_operational_state

Command:

```bash
MAMMOTH_BENCH_RECORDS=10000 MAMMOTH_BENCH_DEAD_LETTERS=1000 MAMMOTH_BENCH_CHECKPOINT_INTERVAL=100 bundle exec ruby benchmark/sqlite_operational_state.rb
```

### Trial 1

- Status: 0
- Output: `sqlite_operational_state-trial-1.out`

| records | dead_letters | checkpoint_interval | delivered_write_seconds | delivered_writes_per_second | duplicate_check_seconds | duplicate_checks_per_second | dead_letter_write_seconds | dead_letter_writes_per_second | delivered_envelopes | dead_letters_total | checkpoints | sqlite_bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 10000 | 1000 | 100 | 6.133534 | 1630.38 | 0.80739 | 12385.59 | 0.604445 | 1654.41 | 10000 | 1000 | 1 | 3809280 |

## observability_snapshot

Command:

```bash
MAMMOTH_BENCH_DELIVERED=10000 MAMMOTH_BENCH_DEAD_LETTERS=1000 MAMMOTH_BENCH_SNAPSHOTS=100 bundle exec ruby benchmark/observability_snapshot.rb
```

### Trial 1

- Status: 0
- Output: `observability_snapshot-trial-1.out`

| delivered | dead_letters | snapshots | readiness_seconds | readiness_per_second | metrics_seconds | metrics_per_second | sqlite_bytes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 10000 | 1000 | 100 | 0.009632 | 10381.57 | 0.133933 | 746.64 | 3723264 |

## dlq_replay

Command:

```bash
MAMMOTH_BENCH_DEAD_LETTERS=1000 MAMMOTH_BENCH_DESTINATIONS=2 MAMMOTH_BENCH_DELIVERY_UNIT=transaction MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 bundle exec ruby benchmark/dlq_replay.rb
```

### Trial 1

- Status: 0
- Output: `dlq_replay-trial-1.out`

| dead_letters | destinations | delivery_unit | elapsed_seconds | replayed_per_second | pending | resolved | delivered_envelopes | sqlite_bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1000 | 2 | "transaction" | 0.97059 | 1030.3 | 0 | 1000 | 1000 | 2551808 |
