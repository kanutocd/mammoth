# frozen_string_literal: true

require "json"
require "time"

module Mammoth
  # Persists failed deliveries in Mammoth's SQLite dead letter queue.
  class DeadLetterStore
    attr_reader :sqlite_store

    # @param sqlite_store [Mammoth::SQLiteStore] bootstrapped SQLite store
    def initialize(sqlite_store)
      @sqlite_store = sqlite_store
    end

    # Store a failed delivery.
    #
    # @param event [Hash] normalized event payload
    # @param destination_name [String] destination name
    # @param error [Exception, nil] delivery failure
    # @param retry_count [Integer] number of delivery attempts
    # @return [Integer] inserted dead letter id
    def write(event:, destination_name:, error: nil, retry_count: 0, serializer: EventSerializer) # rubocop:disable Metrics/MethodLength
      now = Time.now.utc.iso8601
      payload = serializer.call(event)
      database.execute(
        <<~SQL,
          INSERT INTO dead_letters(
            event_id,
            source_name,
            destination_name,
            operation,
            namespace,
            entity,
            source_position,
            payload_json,
            error_class,
            error_message,
            retry_count,
            status,
            failed_at,
            updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)
        SQL
        [
          payload.fetch("event_id"),
          payload.fetch("source"),
          destination_name,
          payload["operation"] || payload["type"],
          payload["namespace"],
          payload["entity"],
          payload["source_position"],
          JSON.generate(payload),
          error&.class&.name,
          error&.message,
          retry_count,
          now,
          now
        ]
      )
      database.last_insert_row_id
    end

    # Fetch pending dead letters.
    #
    # @param limit [Integer] maximum number of rows
    # @return [Array<Hash>] pending dead letter rows
    def pending(limit: 100)
      database.execute(
        "SELECT * FROM dead_letters WHERE status = ? ORDER BY failed_at ASC LIMIT ?",
        ["pending", limit]
      )
    end

    # Count dead letters by status.
    #
    # @param status [String, nil] optional status
    # @return [Integer] dead letter count
    def count(status: nil)
      if status
        database.get_first_value("SELECT COUNT(*) FROM dead_letters WHERE status = ?", [status])
      else
        database.get_first_value("SELECT COUNT(*) FROM dead_letters")
      end
    end

    # Mark a dead letter as resolved.
    #
    # @param id [Integer] dead letter id
    # @return [void]
    def resolve(id)
      update_status(id, "resolved")
    end

    # Mark a dead letter as ignored.
    #
    # @param id [Integer] dead letter id
    # @return [void]
    def ignore(id)
      update_status(id, "ignored")
    end

    private

    def database
      sqlite_store.bootstrap!.database
    end

    def update_status(id, status)
      database.execute(
        "UPDATE dead_letters SET status = ?, updated_at = ? WHERE id = ?",
        [status, Time.now.utc.iso8601, id]
      )
    end
  end
end
