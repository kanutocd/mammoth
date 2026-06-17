# frozen_string_literal: true

require "test_helper"

module Mammoth
  class TransactionEnvelopeSerializerTest < Minitest::Test
    def test_serializes_hash_backed_envelope_values
      envelope = HashBackedEnvelope.new(
        "event_id" => "tx-event-1",
        "transaction_id" => "tx-1",
        "source_position" => "0/ABC",
        "committed_at" => Time.utc(2026, 6, 17, 1, 2, 3),
        "metadata" => { "tenant" => "acme" },
        "events" => [sample_event("event-1", "0/001")]
      )

      payload = TransactionEnvelopeSerializer.call(envelope)

      assert_equal "tx-event-1", payload.fetch("event_id")
      assert_equal "transaction.committed", payload.fetch("type")
      assert_equal "tx-1", payload.fetch("transaction_id")
      assert_equal "0/ABC", payload.fetch("source_position")
      assert_equal "0/ABC", payload.fetch("commit_lsn")
      assert_equal "2026-06-17T01:02:03Z", payload.fetch("committed_at")
      assert_equal({ "tenant" => "acme" }, payload.fetch("metadata"))
    end

    def test_uses_commit_lsn_and_commit_time_when_source_position_is_absent
      envelope = MethodEnvelope.new(
        events: [sample_event("event-1", "0/001")],
        transaction_id: "tx-2",
        commit_lsn: "0/COMMIT",
        commit_time: Time.utc(2026, 6, 17, 4, 5, 6)
      )

      payload = TransactionEnvelopeSerializer.call(envelope)

      assert_equal "0/COMMIT", payload.fetch("source_position")
      assert_equal "2026-06-17T04:05:06Z", payload.fetch("committed_at")
    end

    def test_falls_back_to_last_event_position_and_default_source
      envelope = MethodEnvelope.new(
        events: [sample_event("event-1", "0/001", source: nil), sample_event("event-2", "0/002", source: nil)],
        transaction_id: "tx-3",
        commit_lsn: nil,
        commit_time: "2026-06-17T07:08:09Z"
      )

      payload = TransactionEnvelopeSerializer.call(envelope)

      assert_equal "0/002", payload.fetch("source_position")
      assert_equal EventSerializer::DEFAULT_SOURCE, payload.fetch("source")
      assert_equal "2026-06-17T07:08:09Z", payload.fetch("committed_at")
      assert_equal({}, payload.fetch("metadata"))
      assert_match(/transaction.committed/, TransactionEnvelopeSerializer.new(envelope).to_json)
    end

    def test_serializes_plain_envelope_without_to_h_or_positions
      envelope = PlainEnvelope.new(
        events: [{ "event_id" => "event-1", "operation" => "insert" }],
        transaction_id: "tx-plain"
      )

      payload = TransactionEnvelopeSerializer.call(envelope)

      assert_equal "tx-plain", payload.fetch("transaction_id")
      assert_nil payload.fetch("source_position")
      assert_equal 1, payload.fetch("event_count")
    end


    def test_serializes_envelope_without_to_h_and_without_event_position
      envelope = ObjectEnvelope.new(
        events: [{ "event_id" => "event-no-position", "operation" => "insert" }],
        transaction_id: "tx-object"
      )

      payload = TransactionEnvelopeSerializer.call(envelope)

      assert_equal "tx-object", payload.fetch("transaction_id")
      assert_nil payload.fetch("source_position")
      assert_equal EventSerializer::DEFAULT_SOURCE, payload.fetch("source")
      assert_equal({}, payload.fetch("metadata"))
    end

    private

    def sample_event(event_id, position, source: "postgresql")
      {
        "event_id" => event_id,
        "source" => source,
        "operation" => "insert",
        "namespace" => "public",
        "entity" => "orders",
        "source_position" => position,
        "data" => { "id" => event_id }
      }.compact
    end

    class HashBackedEnvelope
      attr_reader :events, :transaction_id

      def initialize(values)
        @values = values
        @events = values.fetch("events")
        @transaction_id = values.fetch("transaction_id")
      end

      def to_h = @values
    end

    PlainEnvelope = Data.define(:events, :transaction_id)

    class ObjectEnvelope
      attr_reader :events, :transaction_id

      def initialize(events:, transaction_id:)
        @events = events
        @transaction_id = transaction_id
      end
    end

    MethodEnvelope = Data.define(:events, :transaction_id, :commit_lsn, :commit_time)
  end
end
