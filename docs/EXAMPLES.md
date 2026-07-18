# Examples

Mammoth ships examples that validate different parts of the system.

## Recommended first run: `webhooks-quickstart`

Start with the
[Database Webhooks Quickstart](https://github.com/kanutocd/mammoth/tree/main/webhooks-quickstart)
for a one-command, application-level walkthrough. It includes a Demo Store,
logical-replication-enabled PostgreSQL, Mammoth, an inspectable signed webhook
receiver, visible retry recovery, and an end-to-end smoke test.

```bash
cd webhooks-quickstart
docker compose up --build --wait
```

The examples below focus on individual delivery, continuity, identity, and
operational behaviors after the complete flow is familiar.

## `examples/postgres_webhook`

Purpose:

```text
sample CDC-shaped event
    ↓
Mammoth delivery path
    ↓
webhook receiver
```

Use this when you want a deterministic happy-path delivery demo without running logical replication.
`mammoth deliver-sample` reconstructs the persisted JSON fixture as an exact
`CDC::Core::ChangeEvent` before the delivery runtime receives it.

## `examples/live_postgres_webhook`

Purpose:

```text
PostgreSQL INSERT
    ↓
logical replication
    ↓
Mammoth
    ↓
webhook receiver
```

Use this when you want to validate the real PostgreSQL ingestion path.

This example exercises:

- PostgreSQL logical replication
- pgoutput-client transport
- replication slot usage
- publication subscription
- webhook delivery
- idle replication behavior

## `examples/composite_replica_identity`

Purpose:

```text
composite-key INSERT + UPDATE + DELETE
    ↓
publication catalog inspection
    ↓
ReplicaIdentityResolver
    ↓
TransactionEnvelope webhook
```

Use this when you want to verify live identity normalization for a table with no
`id` column. The `memberships` table uses `(tenant_id, member_uuid)` as its
primary key, and the receiver rejects the payload unless all three operations
contain both identity fields.

This example exercises:

- ordered, catalog-derived replica identity mappings
- composite and non-`id` keys
- key-only `DELETE` old tuples
- transaction-level webhook delivery
- startup publication and replica-identity preflight

Run it with:

```bash
cd examples/composite_replica_identity
docker compose up --build
```

The receiver should report that the composite identity was verified for
`INSERT`, `UPDATE`, and `DELETE`.

## `examples/postgres_observability`

Purpose:

```text
PostgreSQL replication catalogs
    ↕
Mammoth relay + observability process
    ↓
/healthz + /readyz + /metrics
```

Use this when you want to correlate Mammoth's read-only slot readiness and
Prometheus gauges with `pg_replication_slots`, `pg_stat_replication`, and
`pg_publication_tables`.

Run it with:

```bash
cd examples/postgres_observability
docker compose up -d --build
docker compose run --rm postgres_inspector
curl -s http://localhost:9394/readyz
curl -s http://localhost:9394/metrics
```

The relay and observability server share operational-state storage, but
process-local dispatch counters are not transferred between them.

## `examples/schema_evolution`

Purpose:

```text
compatible receiver
    ↓
v1 row → additive DDL → v2 row
    ↓
Mammoth payloads without and with the new field
```

Use this to exercise the safe order for an additive schema rollout: deploy a
consumer that accepts both shapes, apply the migration, and then write the new
column. The example verifies that pgoutput refreshes relation metadata for
later row events while emitting no event for the DDL statement itself.

Run it with:

```bash
cd examples/schema_evolution
docker compose up -d --build
docker compose run --rm producer_v1
docker compose run --rm migrate
docker compose run --rm producer_v2
docker compose logs webhook_receiver
```

The receiver rejects a v1 event containing `currency` and a v2 event that does
not contain `currency: "USD"`.

## `examples/destination_idempotency`

Purpose:

```text
isolated Mammoth ledger A ─┐
                           ├─ duplicate event → one destination side effect
isolated Mammoth ledger B ─┘
```

Use this to distinguish Mammoth's local duplicate-suppression ledger from
destination-owned semantic idempotency. Two delivery processes with independent
SQLite stores send the same stable event ID. The receiver records two HTTP
attempts while a unique constraint and atomic transaction apply the order side
effect once.

Run it with:

```bash
cd examples/destination_idempotency
docker compose down -v
docker compose build delivery_a delivery_b
docker compose up -d --wait webhook_receiver
docker compose run --rm delivery_a
docker compose run --rm delivery_b
curl -s http://localhost:9301/state
```

The resulting state should contain `delivery_attempts: 2` and
`applied_side_effects: 1`. Re-running the delivery services then demonstrates
that each Mammoth process suppresses duplicates found in its own ledger.

## `examples/transaction_webhook`

Purpose:

```text
PostgreSQL transaction
    ↓
logical replication
    ↓
TransactionEnvelope
    ↓
CDC::Concurrent::ProcessorPool
    ↓
webhook receiver
```

Use this when you want to validate Mammoth transaction-level delivery.

This example exercises:

- PostgreSQL logical replication
- source-adapter-owned transaction envelope normalization and preservation
- `delivery.unit: transaction`
- `runtime.adapter: concurrent`
- webhook transaction payloads
- contiguous transaction-group checkpoint and acknowledgement behavior

Run it with:

```bash
cd examples/transaction_webhook
docker compose up --build
```

The receiver should log a `transaction.committed` payload with multiple row-level
events in the `events` array.

## `examples/webhook_fanout`

Purpose:

```text
sample CDC-shaped event or TransactionEnvelope
    ↓
Mammoth fanout delivery path
    ↓
primary webhook + audit webhook
```

Use this when you want to inspect the `destinations` configuration shape for
multi-destination webhook fanout. The example is config-only: it demonstrates
the YAML contract, per-destination routing controls, env-backed Authorization
headers, HMAC signing secrets, and retry overrides without adding another
Docker stack.

This example exercises:

- `destinations`
- multiple webhook destinations
- per-destination `header_env`
- per-destination `signing.secret_env`
- per-destination `enabled`
- per-destination `route`
- per-destination `retry`
- independent destination names used by delivered ledgers and dead letters

Validate the config with:

```bash
bundle exec ./exe/mammoth validate examples/webhook_fanout/config/mammoth.yml
```

## `examples/ordering`

Purpose:

```text
PostgreSQL transactions A, B, C
    ↓
TransactionEnvelope delivery
    ↓
cdc-concurrent scheduling
    ↓
preserve_order true vs false
```

Use this to validate the operational tradeoff controlled by:

```yaml
runtime:
  adapter: concurrent
  concurrency: 25
  preserve_order: true
```

With `preserve_order: true`, the receiver should complete transactions in commit order:

```text
A
B
C
```

With `preserve_order: false`, the receiver intentionally makes transaction `A` slow, so `B` and `C` may complete first. This demonstrates the throughput-oriented mode where strict delivery order is not guaranteed.

Run the default ordered example:

```bash
cd examples/ordering
docker compose down -v
docker compose up --force-recreate --build
```

Run the unordered variant:

```bash
cd examples/ordering
docker compose down -v
MAMMOTH_ORDERING_CONFIG=./config/preserve_order_false.yml \
  docker compose up --force-recreate --build
```

## `examples/operational_state`

Purpose:

```text
Mammoth bootstrap
    ↓
SQLite operational database
    ↓
checkpoints + dead_letters + delivered_envelopes schema
```

Use this when you want to inspect Mammoth's local operational memory without running PostgreSQL or a webhook receiver.

Useful commands:

```bash
bundle exec ./exe/mammoth bootstrap examples/operational_state/config/mammoth.yml
bundle exec ./exe/mammoth status examples/operational_state/config/mammoth.yml
sqlite3 examples/operational_state/.sqlite3/mammoth.db ".tables"
```

## `examples/failing_webhook_retry`

Purpose:

```text
sample CDC-shaped event
    ↓
Mammoth delivery worker
    ↓
webhook returns 500
    ↓
retry exhaustion
    ↓
SQLite dead letter
    ↓
contiguous checkpoint advances
```

Use this to validate retry and dead-letter behavior.
A persisted dead letter is a durable outcome, so it closes the corresponding
gap in the progress watermark while replay remains operator-controlled.

After running the example, inspect the SQLite database in the Docker volume.

Expected dead-letter shape:

```text
demo-order-1|failing_webhook|insert|public|orders|2|pending|Mammoth::DeliveryError|webhook failing_webhook returned HTTP 500
```

If the same persistent volume is reused across multiple runs, repeated executions may append additional dead-letter records for the same sample event.

Clear the volume for a clean run:

```bash
docker compose down -v
```

## `examples/kubernetes_helm`

Purpose:

```text
Helm chart
    ↓
Kubernetes Deployment
    ↓
PVC-backed SQLite operational state
```

Use this to validate chart rendering, installation, and persistence wiring.

The example expects you to provide real deployment dependencies such as PostgreSQL, secrets, publications, and webhook destinations.

Every live example defines a primary key on its published table. Production
tables that publish `UPDATE` or `DELETE` must likewise use a primary key, an
eligible selected replica-identity index, or `REPLICA IDENTITY FULL`; Mammoth
validates this before streaming.

The live examples intentionally do not model DDL delivery, sequence
synchronization, or PostgreSQL subscriber conflict repair. The schema evolution
example models a coordinated migration while explicitly showing that no DDL
event is delivered. Mammoth relays row changes to HTTP destinations: coordinate
schema changes with those consumers, synchronize sequences externally when
building a writable database copy, and use destination idempotency plus
explicit dead-letter replay for delivery conflicts.

## Checkpoint Recovery

`examples/checkpoint_recovery` demonstrates Mammoth restart recovery using the
built-in SQLite operational-state adapter and a permanent PostgreSQL replication
slot. It validates that persisted checkpoints and delivered-envelope ledger
entries suppress replay after Mammoth restarts while later transactions continue
to flow. Mammoth persists the contiguous checkpoint before acknowledging the
same position through pgoutput-client. Restart recovery also preflights the
retained slot; a missing or checkpoint-unreachable slot fails closed instead of
being recreated as though continuity still existed.

## Slot Invalidation Recovery

`examples/slot_invalidation_recovery` demonstrates the fail-closed path when
PostgreSQL invalidates an idle logical replication slot and the explicit
operator reconciliation required afterward. Mammoth refuses to stream across
the invalidated slot, the example drops that slot and clears Mammoth's durable
checkpoint state outside the transport boundary, and a fresh startup
auto-creates a new safe baseline before later transactions resume.
