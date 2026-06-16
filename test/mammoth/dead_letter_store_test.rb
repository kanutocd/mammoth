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
