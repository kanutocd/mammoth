# Mammoth Examples

Mammoth examples are intentionally split by operator story. The OSS MVP focuses
on reliable webhook delivery and local SQLite operational memory while keeping
unit tests Docker-free.

## Available examples

| Example | Purpose | Runs live PostgreSQL replication? |
| --- | --- | --- |
| [`postgres_webhook`](./postgres_webhook) | Sample CDC-shaped event delivered to a webhook with SQLite checkpoints. | No |
| [`live_postgres_webhook`](./live_postgres_webhook) | Full PostgreSQL logical replication shape using `mammoth start`. | Yes |
| [`transaction_webhook`](./transaction_webhook) | Live PostgreSQL transaction delivered as one TransactionEnvelope webhook payload through the concurrent runtime. | Yes |
| [`webhook_fanout`](./webhook_fanout) | Config-only example for multi-destination webhook fanout with env-backed auth and signing. | No |
| [`ordering`](./ordering) | Demonstrates `runtime.preserve_order` tradeoffs for transaction-level delivery. | Yes |
| [`failing_webhook_retry`](./failing_webhook_retry) | Retry exhaustion and dead-letter persistence when a webhook fails. | No |
| [`operational_state`](./operational_state) | SQLite bootstrap/status workflow for checkpoints and dead letters. | No |
| [`kubernetes_helm`](./kubernetes_helm) | Helm deployment walkthrough using the public chart. | Deployment only |

## Boundary

The sample examples use `mammoth deliver-sample` so delivery, checkpointing, and
DLQ behavior can be exercised without requiring Docker or PostgreSQL in the unit
suite. The live replication examples are the place where PostgreSQL, logical
replication, TransactionEnvelope delivery, and the CDC Ecosystem source adapter
are intentionally exercised together.


## Checkpoint Recovery

`examples/checkpoint_recovery` demonstrates Mammoth restart recovery using a persistent SQLite checkpoint store and permanent PostgreSQL replication slot. It validates that delivered transactions are not replayed after Mammoth restarts and that later transactions continue to flow.
