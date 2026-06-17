# Quick Start

This guide shows the shortest path from a PostgreSQL table change to a Mammoth webhook delivery.

## 1. Install Mammoth

From RubyGems:

```bash
gem install mammoth
```

Or use the container image:

```bash
docker pull ghcr.io/kanutocd/mammoth:v0.1.0
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

Export the password referenced by `postgres.password_env`:

```bash
export MAMMOTH_POSTGRES_PASSWORD=secret
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

## 8. Inspect status

```bash
mammoth status config/mammoth.yml
```

This reports operational state from the SQLite database.
