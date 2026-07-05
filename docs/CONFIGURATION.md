# Configuration

Mammoth uses YAML configuration validated by JSON Schema.

Add this comment at the top of config files to enable editor validation when using a YAML language server:

```yaml
# yaml-language-server: $schema=./mammoth.schema.json
```

## Full example

```yaml
mammoth:
  name: local_mammoth

postgres:
  host: localhost
  port: 5432
  database: app_development
  username: mammoth
  password_env: MAMMOTH_POSTGRES_PASSWORD

replication:
  slot: mammoth_prod
  publications:
    - mammoth_publication
  auto_create_slot: false
  temporary_slot: false
  feedback_interval: 10.0

delivery:
  unit: transaction
  ordering:
    scope: transaction

runtime:
  adapter: concurrent
  concurrency: 1
  preserve_order: true
  timeout_seconds:

webhook:
  name: primary_webhook
  url: https://example.com/webhooks/postgres
  timeout_seconds: 5
  headers:
    X-Mammoth-Source: local_mammoth
  header_env:
    Authorization: MAMMOTH_WEBHOOK_AUTHORIZATION
  signing:
    algorithm: hmac_sha256
    secret_env: MAMMOTH_WEBHOOK_SIGNING_SECRET
    signature_header: X-Mammoth-Signature
    timestamp_header: X-Mammoth-Timestamp

retry:
  max_attempts: 5
  schedule_seconds:
    - 1
    - 5
    - 30
    - 60
    - 300

sqlite:
  path: data/mammoth.db

logging:
  level: info
```

## Sections

### `mammoth`

```yaml
mammoth:
  name: local_mammoth
```

`name` identifies this Mammoth instance in operational state and logs.

### `postgres`

```yaml
postgres:
  host: localhost
  port: 5432
  database: app_development
  username: mammoth
  password_env: MAMMOTH_POSTGRES_PASSWORD
```

`password_env` names the environment variable containing the PostgreSQL password. Mammoth reads the password from the environment rather than storing it directly in YAML.

### `replication`

```yaml
replication:
  slot: mammoth_prod
  publications:
    - mammoth_publication
  auto_create_slot: false
  temporary_slot: false
  feedback_interval: 10.0
```

- `slot` is the logical replication slot name.
- `publications` is the list of PostgreSQL publications to subscribe to.
- `auto_create_slot` controls whether Mammoth attempts to create the slot.
- `temporary_slot` controls whether the replication slot is temporary.
- `feedback_interval` controls standby feedback cadence in seconds.

### `webhook`

```yaml
webhook:
  name: primary_webhook
  url: https://example.com/webhooks/postgres
  timeout_seconds: 5
  headers:
    X-Mammoth-Source: local_mammoth
  header_env:
    Authorization: MAMMOTH_WEBHOOK_AUTHORIZATION
  signing:
    algorithm: hmac_sha256
    secret_env: MAMMOTH_WEBHOOK_SIGNING_SECRET
```

`name` is used in operational records such as dead letters. `url` is the destination endpoint.

`headers` adds static HTTP headers to every webhook request. Use it only for
non-secret values. `header_env` maps header names to environment variable names,
which is the recommended path for API keys and bearer tokens.

`signing` enables HMAC-SHA256 request signing. Mammoth signs
`<timestamp>.<json request body>` with the secret read from `secret_env`, sends
the timestamp in `timestamp_header`, and sends a `sha256=<hex digest>` signature
in `signature_header`.

### `delivery`

```yaml
delivery:
  unit: transaction
  ordering:
    scope: transaction
```

`unit` controls whether Mammoth delivers individual events or complete
transaction envelopes. `transaction` is the safer default because checkpointing
advances after the transaction payload succeeds.

`ordering.scope` describes the order Mammoth asks the delivery runtime to
preserve. Supported values are `global`, `transaction`, `relation`,
`primary_key`, and `none`.

### `runtime`

```yaml
runtime:
  adapter: concurrent
  concurrency: 1
  preserve_order: true
  batch_size: 1
  timeout_seconds:
```

`adapter` may be `inline` or `concurrent`. The concurrent adapter uses
`cdc-concurrent` for downstream webhook work only; it does not create extra
PostgreSQL replication slots or replication connections.

`concurrency` controls downstream delivery parallelism. `preserve_order` keeps
configured delivery ordering when supported by the runtime. `batch_size`
controls how many work units are submitted to the concurrent runtime together.
`timeout_seconds` is optional; leave it blank to rely on destination-specific
timeouts.

### `retry`

```yaml
retry:
  max_attempts: 5
  schedule_seconds:
    - 1
    - 5
    - 30
    - 60
    - 300
```

Mammoth retries failed deliveries according to this schedule. When retries are exhausted, failed events are persisted as dead letters.

### `sqlite`

```yaml
sqlite:
  path: data/mammoth.db
```

SQLite stores operational memory: schema migrations, checkpoints, and dead letters.

### `logging`

```yaml
logging:
  level: info
```

Valid levels are:

```text
debug
info
warn
error
```

## Validate config

```bash
mammoth validate config/mammoth.yml
```


## Observability

Mammoth can expose optional health, readiness, and metrics endpoints.

```yaml
observability:
  host: 0.0.0.0
  port: 9393
```

`host` controls the bind address. `port` controls the HTTP port. The endpoints
are started with `mammoth observability CONFIG` and include `/healthz`,
`/readyz`, and `/metrics`.
