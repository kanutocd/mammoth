# frozen_string_literal: true

require "test_helper"

module Mammoth
  class CDCIntegrationTest < Minitest::Test
    def test_serializer_projects_cdc_core_change_event_shape
      event = FakeChangeEvent.new

      payload = EventSerializer.call(event)

      assert_equal "insert", payload.fetch("operation")
      assert_equal "public", payload.fetch("namespace")
      assert_equal "orders", payload.fetch("entity")
      assert_equal({ "id" => 1 }, payload.fetch("identity"))
      assert_equal "0/16F4A8B0", payload.fetch("source_position")
      assert_equal({ "id" => 1, "total" => 100 }, payload.fetch("data"))
    end

    def test_consumer_flattens_transaction_envelopes_into_events
      events = [FakeChangeEvent.new, FakeChangeEvent.new]
      envelope = FakeTransactionEnvelope.new(events)
      consumer = ReplicationConsumer.new(Configuration.load(fixture_config_path), source: [envelope])
      consumed = []

      count = consumer.start { |event| consumed << event }

      assert_equal 2, count
      assert_equal events, consumed
    end

    class FakeChangeEvent
      def to_h
        {
          "operation" => :insert,
          "schema" => "public",
          "table" => "orders",
          "primary_key" => { "id" => 1 },
          "commit_lsn" => "0/16F4A8B0",
          "new_values" => { "id" => 1, "total" => 100 },
          "metadata" => { "source" => "pgoutput" }
        }
      end
    end

    FakeTransactionEnvelope = Data.define(:events) do
      def transaction_id = "tx-1"
    end
  end
end
