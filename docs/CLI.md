# CLI Reference

Mammoth exposes a small operator-facing command surface.

```text
mammoth version
mammoth validate CONFIG
mammoth bootstrap CONFIG
mammoth status CONFIG
mammoth start CONFIG
mammoth deliver-sample CONFIG EVENT_JSON
mammoth dead-letters list CONFIG [--status STATUS] [--destination NAME] [--failed-after ISO8601] [--failed-before ISO8601] [--limit N]
mammoth dead-letters show CONFIG ID
mammoth dead-letters replay CONFIG [ID ...] [--destination NAME] [--status STATUS] [--failed-after ISO8601] [--failed-before ISO8601] [--limit N]
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

Initializes the configured operational-state adapter.

```bash
mammoth bootstrap config/mammoth.yml
```

With the built-in `sqlite` adapter, this creates tables such as:

```text
schema_migrations
checkpoints
dead_letters
delivered_envelopes
```

## `mammoth status CONFIG`

Reads Mammoth operational state through the configured adapter.

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

Deserializes one persisted CDC JSON event into an exact
`CDC::Core::ChangeEvent`, then sends it through Mammoth's delivery path.

```bash
mammoth deliver-sample \
  examples/postgres_webhook/config/mammoth.yml \
  examples/postgres_webhook/events/order_insert.json
```

This command is useful for demos, smoke tests, and delivery-path validation. It does not start PostgreSQL logical replication.

## `mammoth dead-letters`

Inspect and replay failed deliveries through the configured operational-state
adapter.

```bash
mammoth dead-letters list config/mammoth.yml
mammoth dead-letters show config/mammoth.yml 12
mammoth dead-letters replay config/mammoth.yml 12
```

`list` shows pending rows by default. Pass `--status resolved`, `--status ignored`, or `--status all` to inspect other records. Use `--destination`, `--failed-after`, `--failed-before`, and `--limit` to narrow the result set.

`replay` reconstructs the stored payload as an exact `CDC::Core::ChangeEvent`
or `CDC::Core::TransactionEnvelope`, re-delivers it through the current Mammoth
configuration, and marks the row resolved on success. Passing explicit IDs
replays those rows. Without IDs, replay uses the same filters as `list`, so
operators can replay a specific destination, status, and failed-at time window.

If the current configuration disables the destination or its route no longer
matches the payload, replay reports `skipped` and leaves the row pending.


## Observability server

Start the optional health, readiness, and metrics HTTP server:

```bash
bundle exec ./exe/mammoth observability config/mammoth.example.yml
```

Endpoints:

- `GET /healthz`
- `GET /readyz`
- `GET /metrics`

The server reads Mammoth's configured operational-state adapter and inspects
the configured PostgreSQL slot for readiness and retained-WAL metrics. It does
not start a replication stream or mutate slot lifecycle.
