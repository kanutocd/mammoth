# frozen_string_literal: true

require "test_helper"

module Mammoth
  class TransactionEnvelopeSerializerTest < Minitest::Test
    def test_serializes_exact_core_transaction_envelope
      committed_at = Time.utc(2026, 6, 17, 1, 2, 3)
      envelope = core_envelope(
        events: [core_event(event_id: "event-1", source_position: "0/001")],
        transaction_id: "tx-1",
        commit_lsn: "0/ABC",
        committed_at: committed_at,
        metadata: { "event_id" => "tx-event-1", "tenant" => "acme" }
      )
      payload = TransactionEnvelopeSerializer.call(envelope)

      assert_equal "tx-event-1", payload.fetch("event_id")
      assert_equal "transaction.committed", payload.fetch("type")
      assert_equal "tx-1", payload.fetch("transaction_id")
      assert_equal "0/ABC", payload.fetch("source_position")
      assert_equal "0/ABC", payload.fetch("commit_lsn")
      assert_equal "2026-06-17T01:02:03Z", payload.fetch("committed_at")
      assert_equal({ "event_id" => "tx-event-1", "tenant" => "acme" }, payload.fetch("metadata"))
    end

    def test_falls_back_to_last_core_event_position_and_defaults
      envelope = core_envelope(
        events: [
          core_event(event_id: "event-1", source_position: "0/001"),
          core_event(event_id: "event-2", source_position: "0/002")
        ],
        transaction_id: "tx-2",
        commit_lsn: nil
      )
      payload = TransactionEnvelopeSerializer.call(envelope)

      assert_equal "0/002", payload.fetch("source_position")
      assert_equal EventSerializer::DEFAULT_SOURCE, payload.fetch("source")
      refute_empty payload.fetch("committed_at")
      assert_equal({}, payload.fetch("metadata"))
      assert_match(/transaction.committed/, TransactionEnvelopeSerializer.new(envelope).to_json)
    end

    def test_serializes_empty_core_envelope
      envelope = core_envelope(events: [], transaction_id: "tx-empty")
      payload = TransactionEnvelopeSerializer.call(envelope)

      assert_nil payload.fetch("source_position")
      assert_equal 0, payload.fetch("event_count")
    end

    def test_rejects_non_core_envelopes
      error = assert_raises(ArgumentError) { TransactionEnvelopeSerializer.call(Object.new) }

      assert_match(/CDC::Core::TransactionEnvelope/, error.message)
    end
  end
end
