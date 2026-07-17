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

## Endpoints

### `GET /healthz`

Liveness endpoint. It confirms that the observability process is running.

Example response:

```json
{
  "status": "ok",
  "service": "mammoth",
  "name": "local_mammoth",
  "version": "0.9.0",
  "checked_at": "2026-07-06T00:00:00Z"
}
```

### `GET /readyz`

Readiness endpoint. It calls `ready?` on the configured operational-state
adapter and reports the adapter's generic summary when ready.

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
  "checked_at": "2026-07-17T00:00:00Z"
}
```

Unready response status code:

```text
503
```

Unready responses use `"operational_state": "error"` and identify the selected
adapter without exposing backend-specific field names.

Readiness is intentionally local. It does not create a PostgreSQL replication
connection and does not deliver events.

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
```

The dispatch counters come from `Mammoth::MetricsObserver`, which implements
the canonical `CDC::Core::Observer` hooks. Mammoth maps the core metric
vocabulary to these Prometheus counters:

- `cdc_core.dispatch.started` → `mammoth_dispatch_started_total`
- `cdc_core.dispatch.succeeded` → `mammoth_dispatch_succeeded_total`
- `cdc_core.dispatch.failed` → `mammoth_dispatch_failed_total`
- `cdc_core.dispatch.skipped` → `mammoth_dispatch_skipped_total`

## Operational model

The observability server resolves the configured operational-state adapter. It
does not open SQLite or construct concrete stores itself. With the built-in
`sqlite` adapter, it is safe to run as a separate process that points at the
same SQLite path used by the relay.

The endpoints expose local relay state only:

- checkpoint row count
- dead-letter row counts
- delivered-envelope ledger row count
- destination-labeled dead-letter and delivered-envelope counts
- started, succeeded, failed, and skipped dispatch counters with canonical core tags
- configured operational-state adapter readiness

Dispatch counters are process-local. A snapshot created with the same
`DispatchMetrics` registry as the running application exposes them. A separate
`mammoth observability` process can always expose adapter-backed gauges, but it
does not inherit another process's in-memory dispatch counters.

The endpoints do not inspect PostgreSQL replication slots, send feedback, replay
dead letters, or mutate delivery state.
