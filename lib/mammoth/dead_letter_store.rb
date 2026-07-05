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
    def pending(limit: 100, destination: nil, failed_after: nil, failed_before: nil)
      rows(status: "pending", limit: limit, destination: destination, failed_after: failed_after,
           failed_before: failed_before)
    end

    # Fetch dead letters, optionally filtered by status.
    #
    # @param status [String, nil] optional dead-letter status filter
    # @param limit [Integer] maximum number of rows
    # @return [Array<Hash>] dead letter rows
    def rows(status: nil, limit: 100, destination: nil, failed_after: nil, failed_before: nil)
      where, values = row_filters(status:, destination:, failed_after:, failed_before:)
      database.execute(
        "SELECT * FROM dead_letters#{where} ORDER BY failed_at ASC LIMIT ?",
        values + [limit]
      )
    end

    # Fetch one dead letter by id.
    #
    # @param id [Integer] dead letter id
    # @return [Hash, nil] dead letter row
    def fetch(id)
      database.get_first_row("SELECT * FROM dead_letters WHERE id = ?", [id])
    end

    # Count dead letters by status.
    #
    # @param status [String, nil] optional status
    # @return [Integer] dead letter count
    def count(status: nil, destination: nil)
      where, values = row_filters(status:, destination:)
      database.get_first_value("SELECT COUNT(*) FROM dead_letters#{where}", values)
    end

    # Count dead letters grouped by destination.
    #
    # @param status [String, nil] optional status filter
    # @return [Array<Hash>] rows with destination_name and count
    def counts_by_destination(status: nil)
      where, values = row_filters(status:)
      database.execute(
        "SELECT destination_name, COUNT(*) AS count FROM dead_letters#{where} GROUP BY destination_name",
        values
      )
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

    def row_filters(status: nil, destination: nil, failed_after: nil, failed_before: nil)
      predicates = [] # : Array[String]
      values = [] # : Array[untyped]

      unless status.nil? || status == "all"
        predicates << "status = ?"
        values << status
      end
      if destination
        predicates << "destination_name = ?"
        values << destination
      end
      if failed_after
        predicates << "failed_at >= ?"
        values << failed_after
      end
      if failed_before
        predicates << "failed_at <= ?"
        values << failed_before
      end

      [predicates.empty? ? "" : " WHERE #{predicates.join(" AND ")}", values]
    end
  end
end
