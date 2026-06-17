# CLI Reference

Mammoth 0.1.x exposes a small command surface.

```text
mammoth version
mammoth validate CONFIG
mammoth bootstrap CONFIG
mammoth status CONFIG
mammoth start CONFIG
mammoth deliver-sample CONFIG EVENT_JSON
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

Mammoth intentionally does not provide `stop`, `restart`, or `reload` commands in 0.1.x. Those concerns belong to the process manager or orchestrator.

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
