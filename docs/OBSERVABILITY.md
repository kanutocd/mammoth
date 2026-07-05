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
  "version": "0.2.0",
  "checked_at": "2026-07-06T00:00:00Z"
}
```

### `GET /readyz`

Readiness endpoint. It verifies Mammoth can open and inspect the configured
SQLite operational store.

Ready response status code:

```text
200
```

Unready response status code:

```text
503
```

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
```

## Operational model

The observability server reads Mammoth's local SQLite operational database. It
is safe to run as a separate process that points at the same SQLite path used by
the relay.

The endpoints expose local relay state only:

- checkpoint row count
- dead-letter row counts
- delivered-envelope ledger row count
- SQLite readiness

The endpoints do not inspect PostgreSQL replication slots, send feedback, replay
dead letters, or mutate delivery state.
