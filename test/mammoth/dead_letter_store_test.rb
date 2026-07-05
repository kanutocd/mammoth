# frozen_string_literal: true

require "test_helper"

module Mammoth
  class DeadLetterStoreTest < Minitest::Test
    def test_writes_pending_dead_letter
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = DeadLetterStore.new(sqlite)
        event = sample_event

        id = store.write(
          event: event,
          destination_name: "primary_webhook",
          error: RuntimeError.new("boom"),
          retry_count: 5
        )
        row = store.pending.first

        assert_equal 1, id
        assert_equal "pending", row.fetch("status")
        assert_equal "boom", row.fetch("error_message")
        assert_equal 1, store.count(status: "pending")
        assert_equal 1, store.count
      end
    end

    def test_pending_respects_limit
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = DeadLetterStore.new(sqlite)

        store.write(event: sample_event("event-1"), destination_name: "primary_webhook")
        store.write(event: sample_event("event-2"), destination_name: "primary_webhook")

        assert_equal 1, store.pending(limit: 1).size
      end
    end

    def test_writes_dead_letter_without_error_object
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = DeadLetterStore.new(sqlite)

        store.write(event: sample_event, destination_name: "primary_webhook")
        row = store.pending.first

        assert_nil row["error_class"]
        assert_nil row["error_message"]
      end
    end

    def test_resolves_and_ignores_dead_letters
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = DeadLetterStore.new(sqlite)
        first = store.write(event: sample_event("event-1"), destination_name: "primary_webhook")
        second = store.write(event: sample_event("event-2"), destination_name: "primary_webhook")

        store.resolve(first)
        store.ignore(second)

        assert_equal 0, store.count(status: "pending")
        assert_equal 1, store.count(status: "resolved")
        assert_equal 1, store.count(status: "ignored")
      end
    end

    def test_filters_by_destination_and_failed_time_window
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = DeadLetterStore.new(sqlite)
        old_id = store.write(event: sample_event("old"), destination_name: "audit_webhook")
        new_id = store.write(event: sample_event("new"), destination_name: "audit_webhook")
        store.write(event: sample_event("primary"), destination_name: "primary_webhook")
        sqlite.database.execute("UPDATE dead_letters SET failed_at = ? WHERE id = ?", ["2026-07-05T00:00:00Z", old_id])
        sqlite.database.execute("UPDATE dead_letters SET failed_at = ? WHERE id = ?", ["2026-07-06T00:00:00Z", new_id])

        rows = store.rows(
          status: "pending",
          destination: "audit_webhook",
          failed_after: "2026-07-05T12:00:00Z",
          failed_before: "2026-07-06T12:00:00Z"
        )

        assert_equal([new_id], rows.map { |row| row.fetch("id") })
        assert_equal 2, store.count(destination: "audit_webhook")
      end
    end

    def test_counts_by_destination
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = DeadLetterStore.new(sqlite)
        store.write(event: sample_event("event-1"), destination_name: "primary_webhook")
        store.write(event: sample_event("event-2"), destination_name: "audit_webhook")
        store.resolve(1)

        assert_equal(
          { "audit_webhook" => 1 },
          store.counts_by_destination(status: "pending").to_h { |row| [row.fetch("destination_name"), row.fetch("count")] }
        )
      end
    end

    private

    def sample_event(event_id = "event-1")
      {
        "event_id" => event_id,
        "source" => "postgresql",
        "operation" => "insert",
        "namespace" => "public",
        "entity" => "orders",
        "source_position" => "0/16F4A8B0",
        "data" => { "id" => 1 }
      }
    end
  end
end
