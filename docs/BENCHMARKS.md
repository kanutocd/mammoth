# Benchmarks

Mammoth benchmarks are intentionally small and focused. They are meant to prove
specific runtime behavior rather than produce universal performance claims.

## Concurrent Delivery Benchmark

Location:

```text
benchmark/concurrent_delivery.rb
```

Run:

```bash
bundle exec ruby benchmark/concurrent_delivery.rb
```

This benchmark exercises the same downstream execution boundary used by Mammoth
when `runtime.adapter: concurrent` is enabled:

```text
TransactionEnvelope
      ↓
Mammoth::ConcurrentDeliveryRuntime
      ↓
Mammoth::DeliveryProcessor
      ↓
DeliveryWorker-compatible sink
```

The default matrix compares:

```text
concurrency: 1
concurrency: 5
concurrency: 10
concurrency: 25
```

with configurable synthetic sink latency.

## Configuration

```bash
MAMMOTH_BENCH_TRANSACTIONS=5000 \
MAMMOTH_BENCH_EVENTS_PER_TRANSACTION=4 \
MAMMOTH_BENCH_LATENCY_MS=25 \
MAMMOTH_BENCH_CONCURRENCY=1,5,10,25,50 \
MAMMOTH_BENCH_PRESERVE_ORDER=false \
bundle exec ruby benchmark/concurrent_delivery.rb
```

Set `MAMMOTH_BENCH_JSON=1` to emit machine-readable JSON after the table.

## Interpretation

This benchmark should be read as a downstream delivery benchmark:

```text
one upstream replication stream
        ↓
many downstream concurrent deliveries
```

It does not create extra PostgreSQL replication slots or replication
connections. That separation is the core Mammoth runtime story.

## Not Covered

This benchmark does not measure:

- PostgreSQL write throughput
- pgoutput decoding throughput
- network behavior
- retry behavior
- checkpoint recovery
- Toxiproxy failure scenarios

Those should be covered by separate end-to-end examples and resilience tests.

## Findings

The benchmark measures Mammoth's ability to scale downstream delivery throughput while consuming a single PostgreSQL logical replication stream.

### Benchmark Configuration

* 10,000 transactions
* 4 events per transaction
* 40,000 total events
* `preserve_order: false`

---

## Fast Sink (10ms)

Simulates a fast downstream webhook.

| Concurrency | Transactions/sec | Events/sec | Avg Latency (ms) | P95 Latency (ms) | Elapsed (s) |
| ----------- | ---------------: | ---------: | ---------------: | ---------------: | ----------: |
| 1           |            96.50 |     385.98 |           10.204 |           10.404 |     103.631 |
| 5           |           482.26 |    1929.04 |           10.235 |           10.451 |      20.736 |
| 10          |           955.04 |    3820.17 |           10.287 |           11.047 |      10.471 |
| 25          |          2419.65 |    9678.61 |           10.173 |           10.330 |       4.133 |

### Interpretation

Throughput scales nearly linearly as delivery concurrency increases.

At a concurrency level of 25, Mammoth achieves approximately:

* 25x transaction throughput
* 25x event throughput

while maintaining essentially identical delivery latency.

---

## Realistic Webhook (50ms)

Simulates a more realistic external webhook endpoint.

| Concurrency | Transactions/sec | Events/sec | Avg Latency (ms) | P95 Latency (ms) | Elapsed (s) |
| ----------- | ---------------: | ---------: | ---------------: | ---------------: | ----------: |
| 1           |            19.85 |      79.40 |           50.206 |           50.405 |     503.795 |
| 5           |            99.27 |     397.07 |           50.234 |           50.419 |     100.737 |
| 10          |           198.40 |     793.61 |           50.181 |           50.402 |      50.403 |
| 25          |           495.11 |    1980.44 |           50.224 |           50.420 |      20.198 |

### Interpretation

When downstream systems become slow, concurrency becomes increasingly valuable.

With a 50ms delivery latency:

* Concurrency 1 processes only 19.85 transactions/sec.
* Concurrency 25 processes 495.11 transactions/sec.

This demonstrates approximately a 25x throughput increase while maintaining a single PostgreSQL replication stream.

---

## Architectural Implications

Mammoth separates:

PostgreSQL Logical Replication

→ TransactionEnvelope Aggregation

→ Concurrent Delivery Execution

This allows delivery throughput to scale independently from PostgreSQL replication resources.

Increasing delivery concurrency does not require additional logical replication connections.

A single PostgreSQL replication stream can drive thousands of event deliveries per second through the `cdc-concurrent` runtime.


## Key Result

Increasing delivery concurrency from 1 to 25 improved throughput from:

- 19.85 tx/sec
- to 495.11 tx/sec

while maintaining a single PostgreSQL logical replication stream.
