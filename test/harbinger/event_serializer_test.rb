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

    def test_raises_for_non_hash_like_event
      assert_raises(NoMethodError) { EventSerializer.call("not-a-hash") }
    end

    def test_to_json_returns_json_payload
      json = EventSerializer.new("operation" => "delete").to_json

      assert_match(/"operation":"delete"/, json)
    end
  end
end
