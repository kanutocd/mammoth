# frozen_string_literal: true

require "time"

module Mammoth
  # SQLite-backed ledger of downstream deliveries.
  #
  # The PostgreSQL replication boundary is at-least-once. Mammoth therefore
  # keeps a small delivery ledger so a transaction replayed by pgoutput-client
  # after restart does not have to be delivered downstream again.
  class DeliveredEnvelopeStore
    SCHEMA = <<~SQL
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
    SQL

    attr_reader :sqlite_store

    def initialize(sqlite_store)
      @sqlite_store = sqlite_store
      ensure_schema!
    end

    def delivered?(idempotency_key)
      !database.execute(
        "SELECT 1 FROM delivered_envelopes WHERE idempotency_key = ? LIMIT 1",
        [idempotency_key]
      ).empty?
    end

    def record!(idempotency_key:, source_name:, slot_name:, destination_name:, delivery_unit:, transaction_id:,
                source_position:)
      database.execute(
        <<~SQL,
          INSERT OR IGNORE INTO delivered_envelopes(
            idempotency_key, source_name, slot_name, destination_name, delivery_unit,
            transaction_id, source_position, delivered_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        [
          idempotency_key,
          source_name,
          slot_name,
          destination_name,
          delivery_unit,
          transaction_id,
          source_position,
          Time.now.utc.iso8601
        ]
      )
      database.get_first_row(
        "SELECT * FROM delivered_envelopes WHERE idempotency_key = ? LIMIT 1",
        [idempotency_key]
      )
    end

    def all
      database.execute("SELECT * FROM delivered_envelopes ORDER BY id")
    end

    def count
      database.get_first_value("SELECT COUNT(*) FROM delivered_envelopes")
    end

    private

    def ensure_schema!
      database.execute_batch(SCHEMA)
    end

    def database
      sqlite_store.bootstrap!.database
    end
  end
end
