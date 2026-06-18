CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS checkpoints (
  id INTEGER PRIMARY KEY,
  source_name TEXT NOT NULL,
  slot_name TEXT NOT NULL,
  publication_name TEXT NOT NULL,
  last_lsn TEXT,
  updated_at TEXT NOT NULL,

  UNIQUE (source_name, slot_name)
);

CREATE TABLE IF NOT EXISTS dead_letters (
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

CREATE INDEX IF NOT EXISTS idx_dead_letters_status
ON dead_letters(status);

CREATE INDEX IF NOT EXISTS idx_dead_letters_destination
ON dead_letters(destination_name);

CREATE INDEX IF NOT EXISTS idx_dead_letters_source_position
ON dead_letters(source_position);

CREATE INDEX IF NOT EXISTS idx_dead_letters_entity
ON dead_letters(namespace, entity);

CREATE INDEX IF NOT EXISTS idx_dead_letters_failed_at
ON dead_letters(failed_at);


CREATE TABLE IF NOT EXISTS delivered_envelopes (
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

CREATE INDEX IF NOT EXISTS idx_delivered_envelopes_source
ON delivered_envelopes(source_name, slot_name);

CREATE INDEX IF NOT EXISTS idx_delivered_envelopes_destination
ON delivered_envelopes(destination_name);

CREATE INDEX IF NOT EXISTS idx_delivered_envelopes_source_position
ON delivered_envelopes(source_position);
