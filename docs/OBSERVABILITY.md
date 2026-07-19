<!--
# @title Observability
-->

# Observability

Mammoth exposes optional HTTP health, readiness, and metrics endpoints for
operators and orchestrators.

Start the observability server:

```bash
bundle exec ./exe/mammoth observability config/mammoth.example.yml
```

By default the server binds to:

```text
0.0.0.0:9393
```

Configure the bind address and port:

```yaml
observability:
  host: 0.0.0.0
  port: 9393
```

## Runnable monitoring showcase

The recommended first-run application includes an optional monitoring profile
that provisions Prometheus, Grafana, example alert rules, and staged demo
traffic:

```bash
cd webhooks-quickstart
docker compose --profile monitoring up --build --wait
```

Open the local monitoring surfaces:

- Mammoth Grafana dashboard: http://localhost:3001/d/mammoth-quickstart
- Grafana-managed alert rules: http://localhost:3001/alerting/list
- Prometheus query library: http://localhost:9090/consoles/mammoth.html
- Prometheus expression browser: http://localhost:9090/query
- Prometheus alert rules: http://localhost:9090/alerts
- Prometheus recording rules: http://localhost:9090/rules

The source-controlled Prometheus query library displays current values and
provides one-click PromQL graph queries for relay health, slot readiness,
consumer activity, delivery totals and throughput, pending dead letters, WAL
retention and safety budget, and replication progress. The showcase also
records the slot WAL-budget utilization ratio.

Prometheus evaluates example alerts for scrape availability, slot readiness,
WAL-budget pressure, and pending dead letters. Grafana separately evaluates
provisioned, read-only rules for slot readiness, WAL-budget pressure, and
pending dead letters. No contact points are configured, so the quickstart does
not send notifications or external alert traffic.

This profile is a single-node demonstration built from Mammoth's public
observability endpoints. It is not a control plane. The multi-deployment
control plane and its agent belong to the paid Mammoth Platform.

## Endpoints

### `GET /healthz`

Liveness endpoint. It confirms that the observability process is running.

Example response:

```json
{
  "status": "ok",
  "service": "mammoth",
  "name": "local_mammoth",
  "version": "1.3.0",
  "checked_at": "2026-07-06T00:00:00Z"
}
```

### `GET /readyz`

Readiness endpoint. It calls `ready?` on the configured operational-state
adapter and inspects the configured PostgreSQL replication slot through
pgoutput-client.

Ready response status code:

```text
200
```

Example ready response:

```json
{
  "status": "ready",
  "service": "mammoth",
  "name": "local_mammoth",
  "operational_state": "ok",
  "adapter": "sqlite",
  "summary": {
    "adapter": "sqlite",
    "checkpoints": 1,
    "dead_letters": 0,
    "delivered_envelopes": 3,
    "path": "data/mammoth.db",
    "tables": ["schema_migrations", "checkpoints", "dead_letters", "delivered_envelopes"]
  },
  "postgres_slot": {
    "slot_name": "mammoth_prod",
    "present": true,
    "active": true,
    "retained_wal_bytes": 8192,
    "wal_status": "reserved",
    "safe_wal_size": 4096,
    "restart_lsn": "0/10",
    "confirmed_flush_lsn": "0/20",
    "ready": true,
    "reason": null
  },
  "checked_at": "2026-07-17T00:00:00Z"
}
```

Unready response status code:

```text
503
```

Operational-state failures use `"operational_state": "error"`. PostgreSQL
failures retain `"operational_state": "ok"` and include a `postgres_slot`
reason. Missing, inactive, WAL-lost, invalidated, conflicting, and restartless
slots return `503`. Inspection errors also return `503`.

Readiness opens a short catalog connection but does not start a replication
stream, create or drop slots, send feedback, or deliver events.

### `GET /metrics`

Prometheus-compatible text exposition endpoint.

Example metrics:

```text
mammoth_up{mammoth_name="local_mammoth"} 1
mammoth_checkpoints_total{mammoth_name="local_mammoth"} 1
mammoth_dead_letters_total{mammoth_name="local_mammoth"} 0
mammoth_dead_letters_pending_total{mammoth_name="local_mammoth"} 0
mammoth_dead_letters_resolved_total{mammoth_name="local_mammoth"} 0
mammoth_dead_letters_ignored_total{mammoth_name="local_mammoth"} 0
mammoth_delivered_envelopes_total{mammoth_name="local_mammoth"} 3
mammoth_dead_letters_pending_total{mammoth_name="local_mammoth",destination="primary_webhook"} 0
mammoth_delivered_envelopes_total{mammoth_name="local_mammoth",destination="audit_webhook"} 3
mammoth_dispatch_started_total{mammoth_name="local_mammoth",kind="transaction_envelope",size="4",transaction_id="42"} 1
mammoth_dispatch_succeeded_total{mammoth_name="local_mammoth",kind="processor_result",retryable="false",status="success"} 1
mammoth_postgres_slot_inspection_up{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 1
mammoth_postgres_slot_present{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 1
mammoth_postgres_slot_ready{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 1
mammoth_postgres_slot_active{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 1
mammoth_postgres_slot_retained_wal_bytes{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 8192
mammoth_postgres_slot_safe_wal_size_bytes{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 4096
mammoth_postgres_slot_wal_status{mammoth_name="local_mammoth",slot_name="mammoth_prod",wal_status="reserved"} 1
```

PostgreSQL slot metrics are omitted when their source catalog value is null or
unavailable on the running PostgreSQL version.

The dispatch counters come from `Mammoth::MetricsObserver`, which implements
the canonical `CDC::Core::Observer` hooks. Mammoth maps the core metric
vocabulary to these Prometheus counters:

- `cdc_core.dispatch.started` → `mammoth_dispatch_started_total`
- `cdc_core.dispatch.succeeded` → `mammoth_dispatch_succeeded_total`
- `cdc_core.dispatch.failed` → `mammoth_dispatch_failed_total`
- `cdc_core.dispatch.skipped` → `mammoth_dispatch_skipped_total`

## Operational model

The observability server resolves the configured operational-state adapter and
uses Mammoth's PostgreSQL source boundary for read-only slot inspection. It
does not open SQLite or construct concrete stores itself. With the built-in
`sqlite` adapter, run it as a separate process pointing at the same SQLite path
and PostgreSQL configuration used by the relay.

The endpoints expose relay and PostgreSQL source health:

- checkpoint row count
- dead-letter row counts
- delivered-envelope ledger row count
- destination-labeled dead-letter and delivered-envelope counts
- started, succeeded, failed, and skipped dispatch counters with canonical core tags
- configured operational-state adapter readiness
- slot inspection availability, presence, activity, readiness, and WAL status
- retained WAL bytes, safe WAL size, invalidation, and inactivity time
- numeric restart and confirmed-flush LSN positions

Dispatch counters are process-local. A snapshot created with the same
`DispatchMetrics` registry as the running application exposes them. A separate
`mammoth observability` process can always expose adapter-backed gauges, but it
does not inherit another process's in-memory dispatch counters.

The endpoints inspect PostgreSQL replication slots read-only. They do not send
feedback, create or drop slots, replay dead letters, or mutate delivery state.

## Alerting guidance

At minimum, alert when:

- `mammoth_postgres_slot_inspection_up` is `0`;
- `mammoth_postgres_slot_present`, `mammoth_postgres_slot_ready`, or
  `mammoth_postgres_slot_active` is `0` outside an expected maintenance window;
- `mammoth_postgres_slot_invalidated` is `1`;
- `mammoth_postgres_slot_wal_status` reports `lost` or `unreserved`;
- `mammoth_postgres_slot_retained_wal_bytes` grows continuously or exceeds the
  environment's recovery budget; or
- `mammoth_postgres_slot_safe_wal_size_bytes` approaches zero.

Use `mammoth_postgres_slot_inactive_since_timestamp_seconds` to measure
unexpected inactivity. The numeric restart and confirmed-flush LSN gauges help
correlate retained WAL with durable acknowledgement progress; they are
positions, not byte-rate counters.

Mammoth does not expose PostgreSQL filesystem capacity, archive health, or
`catalog_xmin` age. Monitor those through the database and infrastructure
tooling. Server settings such as `max_slot_wal_keep_size` and, where supported,
`idle_replication_slot_timeout` are last-resort database protections: crossing
them can invalidate the slot and force external reconciliation.
