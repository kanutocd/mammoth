# frozen_string_literal: true

require "test_helper"

module Mammoth
  class EventSerializerTest < Minitest::Test
    def test_serializes_exact_core_event
      event = core_event(event_id: "event-1", source_position: "0/ABC", data: { "id" => 1 })
      payload = EventSerializer.call(event)

      assert_equal "event-1", payload.fetch("event_id")
      assert_equal "postgresql", payload.fetch("source")
      assert_equal "insert", payload.fetch("operation")
      assert_equal "public", payload.fetch("namespace")
      assert_equal "orders", payload.fetch("entity")
      assert_equal "0/ABC", payload.fetch("source_position")
      assert_equal({ "id" => 1 }, payload.fetch("data"))
    end

    def test_projects_core_delete_values_and_timestamp
      occurred_at = Time.utc(2026, 6, 16, 1, 2, 3)
      event = core_event(
        operation: :delete,
        table: "payments",
        data: { "id" => 7, "status" => "pending" },
        occurred_at: occurred_at
      )
      payload = EventSerializer.call(event)

      assert_equal "payments", payload.fetch("entity")
      assert_equal({ "id" => 7 }, payload.fetch("identity"))
      assert_equal({ "id" => 7, "status" => "pending" }, payload.fetch("data"))
      assert_equal "2026-06-16T01:02:03Z", payload.fetch("occurred_at")
      assert_equal "delete", payload.fetch("operation")
    end

    def test_projects_persisted_metadata_aliases
      event = core_event(
        metadata: {
          "source" => "custom",
          "source_position" => "0/EXPLICIT",
          "changes" => [{ "column" => "status" }]
        }
      )
      payload = EventSerializer.call(event)

      assert_equal "custom", payload.fetch("source")
      assert_equal "0/1", payload.fetch("source_position")
      assert_equal [{ "column" => "status" }], payload.fetch("changes")
    end

    def test_serializes_column_changes_when_update_has_complete_old_and_new_rows
      event = CDC::Core::ChangeEvent.new(
        operation: :update,
        schema: "public",
        table: "orders",
        old_values: { "id" => 4, "status" => "pending", "total_cents" => 4999 },
        new_values: { "id" => 4, "status" => "paid", "total_cents" => 4999 },
        primary_key: { "id" => 4 }
      )

      changes = EventSerializer.call(event).fetch("changes")

      assert_equal [
        { "name" => "status", "old_value" => "pending", "new_value" => "paid" }
      ], changes
    end

    def test_does_not_infer_column_changes_from_an_incomplete_old_row
      event = CDC::Core::ChangeEvent.new(
        operation: :update,
        schema: "public",
        table: "orders",
        old_values: { "id" => 4 },
        new_values: { "id" => 4, "status" => "paid", "total_cents" => 4999 },
        primary_key: { "id" => 4 }
      )

      assert_empty EventSerializer.call(event).fetch("changes")
    end

    def test_uses_defaults_when_optional_core_values_are_absent
      event = CDC::Core::ChangeEvent.new(operation: :insert, schema: "public", table: "orders")
      payload = EventSerializer.call(event)

      refute_empty payload.fetch("event_id")
      refute_empty payload.fetch("occurred_at")
      assert_equal EventSerializer::DEFAULT_SOURCE, payload.fetch("source")
      assert_equal({}, payload.fetch("data"))
    end

    def test_generates_a_stable_event_id_when_metadata_does_not_supply_one
      event = core_event(
        event_id: nil,
        metadata: { "source" => "pgoutput" },
        transaction_id: 42,
        source_position: "0/ABC"
      )

      first_id = EventSerializer.call(event).fetch("event_id")
      second_id = EventSerializer.call(event).fetch("event_id")

      assert_equal first_id, second_id
      assert_match(/\Aevt_[0-9a-f]{64}\z/, first_id)
    end

    def test_rejects_non_core_events
      error = assert_raises(ArgumentError) { EventSerializer.call(operation: :insert) }

      assert_match(/CDC::Core::ChangeEvent/, error.message)
    end

    def test_to_json_returns_json_payload
      json = EventSerializer.new(core_event(operation: :delete)).to_json

      assert_match(/"operation":"delete"/, json)
    end
  end
end
