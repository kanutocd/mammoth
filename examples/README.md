# Mammoth Examples

Mammoth examples are intentionally split by operator story. The v1 examples
exercise reliable webhook delivery, PostgreSQL continuity safeguards, and local
SQLite operational memory while keeping unit tests Docker-free.

## Available examples

| Example | Purpose | Runs live PostgreSQL replication? |
| --- | --- | --- |
| [`../webhooks-quickstart`](../webhooks-quickstart) | Recommended first-run application with visible signed deliveries, retries, optional provisioned monitoring, adaptation guidance, and an end-to-end smoke test. | Yes |
| [`postgres_webhook`](./postgres_webhook) | Sample CDC-shaped event delivered with SQLite checkpoints and duplicate-suppression ledger. | No |
| [`live_postgres_webhook`](./live_postgres_webhook) | Full PostgreSQL logical replication shape using `mammoth start`. | Yes |
| [`composite_replica_identity`](./composite_replica_identity) | Proves catalog-derived composite identity preservation across live `INSERT`, `UPDATE`, and `DELETE` events. | Yes |
| [`slot_invalidation_recovery`](./slot_invalidation_recovery) | Demonstrates fail-closed restart and explicit operator recovery after PostgreSQL invalidates an idle slot. | Yes |
| [`postgres_observability`](./postgres_observability) | Correlates Mammoth readiness and slot metrics with PostgreSQL replication catalogs. | Yes |
| [`schema_evolution`](./schema_evolution) | Demonstrates a consumer-first additive schema rollout and relation-metadata refresh without implying DDL delivery. | Yes |
| [`destination_idempotency`](./destination_idempotency) | Proves that isolated relay ledgers may both deliver while the destination applies one atomic side effect. | No |
| [`transaction_webhook`](./transaction_webhook) | Live PostgreSQL transaction delivered as one TransactionEnvelope webhook payload through the concurrent runtime. | Yes |
| [`webhook_fanout`](./webhook_fanout) | Config-only fanout example with destination-scoped payload masking, env-backed auth, and signing. | No |
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

Example configurations use `logging.level: info`. Live Compose examples expose
Mammoth’s newline-delimited JSON logs with:

```bash
docker compose logs -f mammoth
```

Set the level to `debug` when diagnosing individual work or WAL
acknowledgements, or to `warn`/`error` for quieter operation. Payload bodies,
configured headers, credentials, signing secrets, and exception messages are
excluded from the records.

Dead-letter replay deliberately follows a different boundary from
`deliver-sample`: it sends the exact destination payload persisted after any
payload policy was applied. Replay does not reconstruct CDC-core work or apply
the current policy a second time.

In those live examples, `pgoutput-source-adapter` owns incremental transaction
buffering and yields CDC-core events or transaction envelopes to Mammoth.
Mammoth's delivery processor returns exact `CDC::Core::ProcessorResult` objects,
and the selected runtime emits canonical `CDC::Core::Observer` notifications
for dispatch metrics. Mammoth preserves pgoutput-client's transport LSN
separately for checkpoints and acknowledgement; a normalized payload
`commit_lsn` is not used as the feedback position.

The live examples define primary keys on every published table, satisfying
Mammoth's startup replica-identity preflight for `UPDATE` and `DELETE`. The
composite replica identity example additionally proves that identity extraction
does not depend on a conventional `id` column.

The slot invalidation recovery example demonstrates the complementary operator
boundary: a lost or invalidated slot must be dropped and re-established outside
Mammoth before streaming can safely resume.

The PostgreSQL observability example runs the relay and read-only observability
server as separate processes. It correlates `/readyz` and Prometheus slot
metrics with `pg_replication_slots`, `pg_stat_replication`, and publication
catalog state while leaving database infrastructure monitoring outside Mammoth.

The schema evolution example demonstrates a consumer-first additive migration.
The receiver accepts both payload shapes before PostgreSQL adds a nullable
column; pgoutput refreshes relation metadata for later row events, but the DDL
statement itself is never delivered.

The destination idempotency example sends one stable event through two isolated
Mammoth operational stores. It demonstrates why the receiver must atomically
deduplicate semantic side effects even when Mammoth has its own local
delivered-envelope ledger.

They do not demonstrate DDL delivery, sequence synchronization, or automatic
destination conflict resolution. PostgreSQL does not replicate DDL or sequence
state through this stream, and Mammoth is an HTTP relay rather than a SQL
subscriber. Coordinate schema changes with receivers, synchronize sequences
externally when constructing a writable database replica, and use destination
idempotency plus Mammoth's dead-letter workflow for conflicts.

## Checkpoint Recovery

`examples/checkpoint_recovery` demonstrates Mammoth restart recovery using the
built-in SQLite operational-state adapter and a permanent PostgreSQL replication
slot. It validates that persisted checkpoints and delivered-envelope ledger
entries suppress replay after Mammoth restarts while later transactions continue
to flow. Contiguous progress is checkpointed before the same position is
acknowledged through pgoutput-client. The retained slot is preflighted on
restart, and a missing or checkpoint-unreachable slot fails closed rather than
being silently recreated.

## Slot Invalidation Recovery

`examples/slot_invalidation_recovery` demonstrates the fail-closed path when
PostgreSQL invalidates an idle logical replication slot and the explicit
operator reconciliation required afterward. Mammoth refuses to stream across
the invalidated slot, the example drops that slot and clears Mammoth's durable
checkpoint state outside the transport boundary, and a fresh startup
auto-creates a new safe baseline before later transactions resume.
