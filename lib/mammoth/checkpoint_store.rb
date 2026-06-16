# frozen_string_literal: true

require "time"

module Mammoth
  # Persists source checkpoints in Mammoth's SQLite operational store.
  class CheckpointStore
    attr_reader :sqlite_store

    # @param sqlite_store [Mammoth::SQLiteStore] bootstrapped SQLite store
    def initialize(sqlite_store)
      @sqlite_store = sqlite_store
    end

    # Insert or update the last successfully delivered source position.
    #
    # @param source_name [String] logical source name
    # @param slot_name [String] PostgreSQL replication slot name
    # @param publication_name [String] PostgreSQL publication name
    # @param last_lsn [String, nil] last delivered LSN/source position
    # @return [Hash] stored checkpoint row
    def write(source_name:, slot_name:, publication_name:, last_lsn:)
      now = Time.now.utc.iso8601
      database.execute(
        <<~SQL,
          INSERT INTO checkpoints(source_name, slot_name, publication_name, last_lsn, updated_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(source_name, slot_name)
          DO UPDATE SET
            publication_name = excluded.publication_name,
            last_lsn = excluded.last_lsn,
            updated_at = excluded.updated_at
        SQL
        [source_name, slot_name, publication_name, last_lsn, now]
      )
      fetch(source_name: source_name, slot_name: slot_name)
    end

    # Fetch a checkpoint row.
    #
    # @param source_name [String] logical source name
    # @param slot_name [String] PostgreSQL replication slot name
    # @return [Hash, nil] checkpoint row or nil
    def fetch(source_name:, slot_name:)
      database.get_first_row(
        "SELECT * FROM checkpoints WHERE source_name = ? AND slot_name = ? LIMIT 1",
        [source_name, slot_name]
      )
    end

    # Count checkpoint rows.
    #
    # @return [Integer] checkpoint count
    def count
      database.get_first_value("SELECT COUNT(*) FROM checkpoints")
    end

    private

    def database
      sqlite_store.bootstrap!.database
    end
  end
end
