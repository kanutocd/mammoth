# frozen_string_literal: true

require "test_helper"

module Mammoth
  class ReplicationConsumerTransactionDeliveryBranchTest < Minitest::Test
    def test_transaction_delivery_wraps_plain_events_in_synthetic_envelopes
      event = {
        operation: "insert",
        commit_lsn: "0/100",
        transaction_id: "tx-100",
        committed_at: "2026-06-17T00:00:00Z",
        metadata: { source: "unit" }
      }
      consumer = ReplicationConsumer.new(source: [event], delivery_unit: :transaction)
      emitted = []

      count = consumer.start { |work| emitted << work }

      assert_equal 1, count
      envelope = emitted.fetch(0)
      assert_equal [event], envelope.events
      assert_equal "tx-100", envelope.transaction_id
      assert_equal "0/100", envelope.commit_lsn
      assert_equal "2026-06-17T00:00:00Z", envelope.commit_time
      assert_equal({ source: "unit" }, envelope.metadata)
    end

    def test_transaction_delivery_wraps_string_keyed_plain_events
      event = {
        "operation" => "update",
        "source_position" => "0/101",
        "event_id" => "event-101",
        "occurred_at" => "2026-06-17T00:00:01Z"
      }
      consumer = ReplicationConsumer.new(source: [event], delivery_unit: :transaction)
      envelope = nil

      consumer.start { |work| envelope = work }

      assert_equal "event-101", envelope.transaction_id
      assert_equal "0/101", envelope.commit_lsn
      assert_equal "2026-06-17T00:00:01Z", envelope.commit_time
      assert_equal({}, envelope.metadata)
    end
  end
end
