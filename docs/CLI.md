# CLI Reference

Mammoth exposes a small operator-facing command surface.

```text
mammoth version
mammoth validate CONFIG
mammoth bootstrap CONFIG
mammoth status CONFIG
mammoth start CONFIG
mammoth deliver-sample CONFIG EVENT_JSON
mammoth dead-letters list CONFIG [--status STATUS] [--limit N]
mammoth dead-letters show CONFIG ID
mammoth dead-letters replay CONFIG [ID ...]
```

## `mammoth version`

Prints the Mammoth version.

```bash
mammoth version
```

## `mammoth validate CONFIG`

Validates a YAML configuration file against Mammoth's JSON Schema.

```bash
mammoth validate config/mammoth.yml
```

Use this before deploying or starting Mammoth.

## `mammoth bootstrap CONFIG`

Initializes the SQLite operational database.

```bash
mammoth bootstrap config/mammoth.yml
```

This creates tables such as:

```text
schema_migrations
checkpoints
dead_letters
```

## `mammoth status CONFIG`

Reads Mammoth operational state from SQLite.

```bash
mammoth status config/mammoth.yml
```

Use this to inspect local operational memory.

## `mammoth start CONFIG`

Starts Mammoth's live PostgreSQL CDC relay.

```bash
mammoth start config/mammoth.yml
```

`start` runs in the foreground. Process lifecycle is managed by your shell, systemd, Docker, Docker Compose, or Kubernetes.

Mammoth intentionally does not provide `stop`, `restart`, or `reload` commands. Those concerns belong to the process manager or orchestrator.

Examples:

```bash
docker compose restart mammoth
kubectl rollout restart deploy/mammoth
systemctl restart mammoth
```

## `mammoth deliver-sample CONFIG EVENT_JSON`

Delivers one CDC-shaped JSON event through Mammoth's delivery path.

```bash
mammoth deliver-sample \
  examples/postgres_webhook/config/mammoth.yml \
  examples/postgres_webhook/events/order_insert.json
```

This command is useful for demos, smoke tests, and delivery-path validation. It does not start PostgreSQL logical replication.

## `mammoth dead-letters`

Inspect and replay failed deliveries stored in SQLite.

```bash
mammoth dead-letters list config/mammoth.yml
mammoth dead-letters show config/mammoth.yml 12
mammoth dead-letters replay config/mammoth.yml 12
```

`list` shows pending rows by default. Pass `--status resolved`, `--status ignored`, or `--status all` to inspect other records. `replay` re-delivers the stored payload through the current Mammoth configuration and marks the row resolved on success.


## Observability server

Start the optional health, readiness, and metrics HTTP server:

```bash
bundle exec ./exe/mammoth observability config/mammoth.example.yml
```

Endpoints:

- `GET /healthz`
- `GET /readyz`
- `GET /metrics`

The server reads Mammoth's SQLite operational state and does not start a
PostgreSQL replication stream.
