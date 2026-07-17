# Operational State

Mammoth stores operational memory in SQLite.

SQLite is used for:

- schema migration state
- checkpoints
- dead letters
- delivered-envelope ledger entries

## Why SQLite?

Mammoth needs durable local state even when running as a small self-hosted service. SQLite provides an inspectable operational database without requiring another service dependency.

## Tables

### `schema_migrations`

Tracks applied operational database migrations.

```sql
CREATE TABLE schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);
```

### `checkpoints`

Stores source progress.

```sql
CREATE TABLE checkpoints (
  id INTEGER PRIMARY KEY,
  source_name TEXT NOT NULL,
  slot_name TEXT NOT NULL,
  publication_name TEXT NOT NULL,
  last_lsn TEXT,
  updated_at TEXT NOT NULL,

  UNIQUE (source_name, slot_name)
);
```

The checkpoint table answers:

```text
Through which source position does Mammoth have contiguous durable outcomes?
```

The shared progress coordinator writes this row only after every earlier work
item has a durable outcome. For PostgreSQL sources, Mammoth persists the
checkpoint before acknowledging the same watermark through pgoutput-client.
Individual destination workers never advance this table independently.
The stored PostgreSQL `last_lsn` is the transport watermark in standard
`HEX/HEX` form, not the decoder's normalized transaction `commit_lsn`.

### `dead_letters`

Stores failed deliveries after retry exhaustion.

```sql
CREATE TABLE dead_letters (
  id INTEGER PRIMARY KEY,
  event_id TEXT NOT NULL,
  source_name TEXT NOT NULL,
  destination_name TEXT NOT NULL,
  operation TEXT NOT NULL,

  namespace TEXT,
  entity TEXT,
  source_position TEXT,

  payload_json TEXT NOT NULL,

  error_class TEXT,
  error_message TEXT,
  retry_count INTEGER NOT NULL DEFAULT 0,

  status TEXT NOT NULL DEFAULT 'pending',
  failed_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,

  CHECK (status IN ('pending', 'resolved', 'ignored')),
  CHECK (retry_count >= 0)
);
```

The dead-letter table answers:

```text
What failed, where was it going, and why did it fail?
```

### `delivered_envelopes`

Stores successfully delivered event or transaction idempotency keys.

```sql
CREATE TABLE delivered_envelopes (
  id INTEGER PRIMARY KEY,
  idempotency_key TEXT NOT NULL,
  source_name TEXT NOT NULL,
  slot_name TEXT NOT NULL,
  destination_name TEXT NOT NULL,
  delivery_unit TEXT NOT NULL,
  transaction_id TEXT,
  source_position TEXT,
  delivered_at TEXT NOT NULL,

  UNIQUE (idempotency_key)
);
```

The delivered-envelope table answers:

```text
Has this event or transaction already been delivered to this destination?
```

Mammoth uses this ledger to skip duplicate downstream delivery when upstream
replication replays already-delivered work after a restart.

## Inspect with sqlite3

Install SQLite locally if needed:

```bash
sudo apt update
sudo apt install sqlite3
```

List tables:

```bash
sqlite3 data/mammoth.db ".tables"
```

Show schema:

```bash
sqlite3 data/mammoth.db ".schema"
```

Inspect dead letters:

```bash
sqlite3 data/mammoth.db \
  "SELECT event_id, destination_name, operation, namespace, entity, retry_count, status, error_class, error_message FROM dead_letters;"
```

Inspect and replay dead letters with Mammoth:

```bash
mammoth dead-letters list config/mammoth.yml
mammoth dead-letters show config/mammoth.yml 12
mammoth dead-letters replay config/mammoth.yml 12
```

Inspect delivered envelopes:

```bash
sqlite3 data/mammoth.db \
  "SELECT idempotency_key, destination_name, delivery_unit, transaction_id, source_position, delivered_at FROM delivered_envelopes;"
```

## Container volume inspection

If the Mammoth image does not include `sqlite3`, inspect the database using a temporary container that mounts the same volume:

```bash
docker run --rm -it \
  -v failing_webhook_retry_mammoth_retry_data:/data \
  alpine:3.20 \
  sh -c "apk add --no-cache sqlite && sqlite3 /data/mammoth.db '.tables'"
```
