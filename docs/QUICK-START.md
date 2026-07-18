# Quick Start

This guide shows the shortest path from a PostgreSQL table change to a Mammoth webhook delivery.

For a one-command, application-level walkthrough with a browser UI, signed
receiver, visible retries, health endpoints, and an adaptation guide, start
with [`../webhooks-quickstart`](../webhooks-quickstart). Continue here when you
want to assemble the same pieces manually.

## 1. Install Mammoth

From RubyGems:

```bash
gem install mammoth
```

Or use the container image:

```bash
docker pull ghcr.io/kanutocd/mammoth:latest
```

## 2. Prepare PostgreSQL

PostgreSQL must be configured for logical replication.

At minimum, PostgreSQL needs:

```text
wal_level = logical
max_replication_slots > 0
max_wal_senders > 0
```

Create a table and publication:

```sql
CREATE TABLE IF NOT EXISTS orders (
  id bigserial PRIMARY KEY,
  status text NOT NULL,
  total_cents integer NOT NULL
);

CREATE PUBLICATION mammoth_publication FOR TABLE orders;
```

The primary key supplies replica identity for published `UPDATE` and `DELETE`
operations. Mammoth validates this before streaming; an eligible selected
unique index or `REPLICA IDENTITY FULL` is also supported.

Create a replication user according to your local security policy. For local development, examples may use a simple user/password setup.

## 3. Configure Mammoth

Create a Mammoth config file:

```yaml
# yaml-language-server: $schema=./mammoth.schema.json

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
  auto_create_slot: true
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
  url: http://localhost:9292/webhook
  timeout_seconds: 5

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

Mammoth checkpoints only contiguous durable delivery outcomes and then
acknowledges the same progress through pgoutput-client. The feedback interval
controls transport cadence, not which position is safe.
`auto_create_slot: true` creates a missing slot only for first-time bootstrap
while no resume LSN or checkpoint exists. Later restarts preflight the retained
slot and fail closed if checkpoint continuity is unavailable.

Export the password referenced by `postgres.password_env`:

```bash
export MAMMOTH_POSTGRES_PASSWORD=secret
```

If your receiver requires authentication, add env-backed headers instead of
placing secrets directly in YAML:

```yaml
webhook:
  header_env:
    Authorization: MAMMOTH_WEBHOOK_AUTHORIZATION
  signing:
    algorithm: hmac_sha256
    secret_env: MAMMOTH_WEBHOOK_SIGNING_SECRET
```

## 4. Validate configuration

```bash
mammoth validate config/mammoth.yml
```

When running from the repository checkout:

```bash
bundle exec ./exe/mammoth validate config/mammoth.example.yml
```

## 5. Bootstrap operational state

```bash
mammoth bootstrap config/mammoth.yml
```

This creates the SQLite database and initializes operational tables.

## 6. Start Mammoth

```bash
mammoth start config/mammoth.yml
```

Mammoth runs in the foreground until the process is terminated by your shell, process manager, Docker, Docker Compose, or Kubernetes.

## 7. Insert a row

```sql
INSERT INTO orders (status, total_cents)
VALUES ('created', 8888);
```

Expected flow:

```text
INSERT
  ↓
PostgreSQL logical replication
  ↓
Mammoth
  ↓
Webhook POST
```

See [Webhook Payloads](file.WEBHOOK-PAYLOADS.html) for the canonical event and
transaction JSON shapes, column-change availability, and destination
idempotency guidance.

## 8. Inspect status

```bash
mammoth status config/mammoth.yml
```

This reports operational state from the SQLite database.

## Before production

- Run `mammoth observability CONFIG` and alert on slot readiness, invalidation,
  retained WAL, and safe WAL size.
- Monitor PostgreSQL disk capacity and catalog-XID age with infrastructure
  tooling.
- Use a permanent, DBA-managed slot after bootstrap and recover the slot and
  Mammoth operational state as one continuity boundary.
- Coordinate schema migrations with webhook consumers; DDL and sequence state
  are not replicated.
- Require destination-side idempotency and use Mammoth's dead-letter workflow
  for failed or conflicting deliveries.
