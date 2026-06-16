# frozen_string_literal: true

require "test_helper"

module Mammoth
  class EventSerializerTest < Minitest::Test
    def test_serializes_symbol_keyed_event
      payload = EventSerializer.call(operation: "insert", namespace: "public", entity: "orders", data: { id: 1 })

      assert_equal "postgresql", payload.fetch("source")
      assert_equal "insert", payload.fetch("operation")
      assert_equal "orders", payload.fetch("entity")
      refute_empty payload.fetch("event_id")
      refute_empty payload.fetch("occurred_at")
    end

    def test_preserves_supplied_event_id_and_metadata
      payload = EventSerializer.call(
        "event_id" => "event-1",
        "source" => "postgresql",
        "operation" => "update",
        "metadata" => { "slot" => "mammoth_prod" }
      )

      assert_equal "event-1", payload.fetch("event_id")
      assert_equal({ "slot" => "mammoth_prod" }, payload.fetch("metadata"))
    end

    def test_projects_cdc_compatibility_aliases
      occurred_at = Time.utc(2026, 6, 16, 1, 2, 3)
      payload = EventSerializer.call(
        schema: "public",
        table: "payments",
        primary_key: { id: 7 },
        commit_lsn: "0/ABC",
        occurred_at: occurred_at,
        old_values: { id: 7, status: "pending" },
        operation: :delete
      )

      assert_equal "public", payload.fetch("namespace")
      assert_equal "payments", payload.fetch("entity")
      assert_equal({ id: 7 }, payload.fetch("identity"))
      assert_equal "0/ABC", payload.fetch("source_position")
      assert_equal({ id: 7, status: "pending" }, payload.fetch("data"))
      assert_equal "2026-06-16T01:02:03Z", payload.fetch("occurred_at")
      assert_equal "delete", payload.fetch("operation")
    end

    def test_prefers_explicit_data_and_changes
      payload = EventSerializer.call(
        "operation" => "update",
        "data" => { "id" => 1, "status" => "paid" },
        "new_values" => { "ignored" => true },
        "changes" => [{ "column" => "status" }]
      )

      assert_equal({ "id" => 1, "status" => "paid" }, payload.fetch("data"))
      assert_equal [{ "column" => "status" }], payload.fetch("changes")
    end

    def test_prefers_explicit_source_position_and_new_values
      payload = EventSerializer.call(
        "operation" => "update",
        "source_position" => "0/EXPLICIT",
        "commit_lsn" => "0/IGNORED",
        "new_values" => { "id" => 2 }
      )

      assert_equal "0/EXPLICIT", payload.fetch("source_position")
      assert_equal({ "id" => 2 }, payload.fetch("data"))
    end

    def test_raises_for_non_hash_like_event
      assert_raises(NoMethodError) { EventSerializer.call("not-a-hash") }
    end

    def test_to_json_returns_json_payload
      json = EventSerializer.new("operation" => "delete").to_json

      assert_match(/"operation":"delete"/, json)
    end
  end
end
