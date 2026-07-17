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

node:
  node_id: local-mammoth-1
  node_name: local-mammoth-dev
  fleet_id: local-dev
  environment: development
  labels:
    region: local
  metadata:
    owner: platform

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

operational_state:
  adapter: sqlite

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

### `node`

```yaml
node:
  node_id: local-mammoth-1
  node_name: local-mammoth-dev
  fleet_id: local-dev
  environment: development
  labels:
    region: local
  metadata:
    owner: platform
```

`node` is optional. It gives the local Mammoth process a stable identity for
status output and future control-plane agents. If omitted, `node_id` defaults
to the host name and `node_name` defaults to `mammoth.name`.

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
- `auto_create_slot` permits first-time slot creation only when no configured
  or persisted resume LSN exists. A missing slot with a checkpoint always fails
  closed instead of being recreated.
- `temporary_slot` controls whether a newly created slot is temporary.
  Temporary slots cannot resume durable Mammoth checkpoints.
- `feedback_interval` controls standby feedback cadence in seconds.

Feedback cadence does not determine the acknowledged position. Mammoth advances
that position only after persisting the contiguous durable-delivery watermark.
Before streaming, Mammoth inspects the configured slot through pgoutput-client
and rejects missing, active, lost, invalidated, incompatible, or
checkpoint-unreachable slots.

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

### `destinations`

Use `destinations` instead of `webhook` when Mammoth should fan out each CDC
work item to multiple webhook receivers.

```yaml
destinations:
  - name: primary_webhook
    type: webhook
    enabled: true
    url: https://example.com/webhooks/postgres
    timeout_seconds: 5
    header_env:
      Authorization: MAMMOTH_PRIMARY_WEBHOOK_AUTHORIZATION
    signing:
      algorithm: hmac_sha256
      secret_env: MAMMOTH_PRIMARY_WEBHOOK_SIGNING_SECRET
  - name: audit_webhook
    type: webhook
    enabled: true
    url: https://audit.example.com/cdc
    timeout_seconds: 5
    route:
      schemas:
        - public
      tables:
        - orders
      operations:
        - insert
        - update
    retry:
      max_attempts: 3
      schedule_seconds:
        - 1
        - 10
```

Mammoth OSS 0.8.x supports webhook destinations. Each enabled destination keeps
independent delivered-ledger, retry, and dead-letter state. Dead-letter replay
targets the destination that originally failed.

`enabled: false` disables new delivery attempts for that destination while still
allowing Mammoth to advance local progress for matching work.

`route` filters delivery by PostgreSQL schema, table, and operation. Omit a
route field to match every value for that field. For transaction delivery, a
destination matches when any event in the transaction matches; Mammoth delivers
the full transaction envelope so downstream receivers keep transaction context.

`retry` overrides the top-level retry policy for one destination. This lets a
slow audit receiver use longer backoff without weakening the primary receiver.

`header_env` and `signing.secret_env` are environment variable names. Mammoth
reads the actual bearer token or signing secret from the process environment at
startup.

### `delivery`

```yaml
delivery:
  unit: transaction
  ordering:
    scope: transaction
```

`unit` controls whether Mammoth delivers individual events or complete
transaction envelopes. Both modes checkpoint only after every delivery in the
source transaction has a durable outcome. `transaction` is recommended when a
consumer needs transaction context in one payload.

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
controls how many work units the runtime execution wrapper accumulates before
submitting them to the selected adapter together.
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

SQLite stores operational memory: schema migrations, checkpoints, dead letters,
and the delivered-envelope ledger.

### `operational_state`

```yaml
operational_state:
  adapter: sqlite
```

`operational_state.adapter` selects the local operational state adapter.
Mammoth OSS ships `sqlite`, which remains the default when this section is
omitted.

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
`/readyz`, and `/metrics`. Readiness combines the configured operational-state
adapter with read-only PostgreSQL slot health. Metrics include retained WAL and
slot status; the observability process never starts a replication stream or
changes slot lifecycle.
