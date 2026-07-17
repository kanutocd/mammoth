# Mammoth Examples

Mammoth examples are intentionally split by operator story. The OSS MVP focuses
on reliable webhook delivery and local SQLite operational memory while keeping
unit tests Docker-free.

## Available examples

| Example | Purpose | Runs live PostgreSQL replication? |
| --- | --- | --- |
| [`postgres_webhook`](./postgres_webhook) | Sample CDC-shaped event delivered with SQLite checkpoints and duplicate-suppression ledger. | No |
| [`live_postgres_webhook`](./live_postgres_webhook) | Full PostgreSQL logical replication shape using `mammoth start`. | Yes |
| [`transaction_webhook`](./transaction_webhook) | Live PostgreSQL transaction delivered as one TransactionEnvelope webhook payload through the concurrent runtime. | Yes |
| [`webhook_fanout`](./webhook_fanout) | Config-only example for multi-destination webhook fanout with env-backed auth and signing. | No |
| [`ordering`](./ordering) | Demonstrates `runtime.preserve_order` tradeoffs for transaction-level delivery. | Yes |
| [`failing_webhook_retry`](./failing_webhook_retry) | Retry exhaustion and dead-letter persistence when a webhook fails. | No |
| [`operational_state`](./operational_state) | SQLite bootstrap/status workflow for checkpoints, delivered envelopes, and dead letters. | No |
| [`kubernetes_helm`](./kubernetes_helm) | Helm deployment walkthrough using the public chart. | Deployment only |

## Boundary

The sample examples use `mammoth deliver-sample`, which reconstructs their JSON
payloads as exact `CDC::Core::ChangeEvent` objects before delivery. This lets
delivery-ledger, contiguous checkpointing, and DLQ behavior be exercised
without requiring Docker or PostgreSQL in the unit suite. The live replication
examples are the place where PostgreSQL acknowledgement, logical replication,
TransactionEnvelope delivery, and the CDC Ecosystem source adapter are
intentionally exercised together.

In those live examples, `pgoutput-source-adapter` owns incremental transaction
buffering and yields CDC-core events or transaction envelopes to Mammoth.
Mammoth's delivery processor returns exact `CDC::Core::ProcessorResult` objects,
and the selected runtime emits canonical `CDC::Core::Observer` notifications
for dispatch metrics.


## Checkpoint Recovery

`examples/checkpoint_recovery` demonstrates Mammoth restart recovery using the
built-in SQLite operational-state adapter and a permanent PostgreSQL replication
slot. It validates that persisted checkpoints and delivered-envelope ledger
entries suppress replay after Mammoth restarts while later transactions continue
to flow. Contiguous progress is checkpointed before the same position is
acknowledged through pgoutput-client.
