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
