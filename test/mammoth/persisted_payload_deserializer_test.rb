# frozen_string_literal: true

require "test_helper"

module Mammoth
  class PersistedPayloadDeserializerTest < Minitest::Test
    def test_deserializes_persisted_event_into_exact_core_event
      event = PersistedPayloadDeserializer.event(
        "event_id" => "event-1",
        "source" => "postgresql",
        "operation" => "update",
        "namespace" => "public",
        "entity" => "orders",
        "identity" => { "id" => 1 },
        "source_position" => "0/10",
        "transaction_id" => "tx-1",
        "occurred_at" => "2026-07-17T01:02:03Z",
        "data" => { "id" => 1, "status" => "paid" },
        "changes" => [{ "column" => "status" }]
      )

      assert_instance_of CDC::Core::ChangeEvent, event
      assert_equal :update, event.operation
      assert_equal "0/10", event.commit_lsn
      assert_equal "tx-1", event.transaction_id
      assert_equal Time.utc(2026, 7, 17, 1, 2, 3), event.occurred_at
      assert_equal({ "id" => 1, "status" => "paid" }, event.new_values)
      assert_equal "event-1", event.metadata[:event_id]
    end

    def test_deserializes_delete_data_as_old_values
      event = PersistedPayloadDeserializer.event(
        operation: :delete,
        schema: "audit",
        table: "entries",
        data: { "id" => 9 }
      )

      assert_equal({ "id" => 9 }, event.old_values)
      assert_nil event.new_values
    end

    def test_deserializes_persisted_transaction_into_exact_core_envelope
      committed_at = Time.utc(2026, 7, 17, 2, 3, 4)
      envelope = PersistedPayloadDeserializer.transaction(transaction_payload(committed_at))

      assert_instance_of CDC::Core::TransactionEnvelope, envelope
      assert_instance_of CDC::Core::ChangeEvent, envelope.events.fetch(0)
      assert_equal "tx-2", envelope.transaction_id
      assert_equal "0/20", envelope.commit_lsn
      assert_equal committed_at, envelope.committed_at
      assert_equal "transaction-event", envelope.metadata[:event_id]
    end

    def test_rejects_invalid_persisted_event
      error = assert_raises(ConfigurationError) do
        PersistedPayloadDeserializer.event("operation" => "insert")
      end

      assert_match(/invalid persisted CDC event/, error.message)
    end

    def test_rejects_invalid_persisted_transaction
      error = assert_raises(ConfigurationError) do
        PersistedPayloadDeserializer.transaction("events" => [])
      end

      assert_match(/invalid persisted CDC transaction/, error.message)
    end

    private

    def transaction_payload(committed_at)
      {
        "event_id" => "transaction-event",
        "type" => TransactionEnvelopeSerializer::PAYLOAD_TYPE,
        "transaction_id" => "tx-2",
        "source_position" => "0/20",
        "committed_at" => committed_at,
        "events" => [
          {
            "event_id" => "event-2",
            "operation" => "insert",
            "namespace" => "public",
            "entity" => "orders",
            "source_position" => "0/20",
            "data" => { "id" => 2 }
          }
        ]
      }
    end
  end
end
