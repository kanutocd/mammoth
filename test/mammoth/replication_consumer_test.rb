# frozen_string_literal: true

require "test_helper"

module Mammoth
  class ReplicationConsumerTest < Minitest::Test
    def test_start_raises_until_cdc_source_is_configured
      consumer = ReplicationConsumer.new

      error = assert_raises(ReplicationError) { consumer.start {} }

      assert_match(/source is not configured/, error.message)
    end

    def test_start_yields_injected_cdc_events
      source = [sample_event("0/1"), sample_event("0/2")]
      consumer = ReplicationConsumer.new(source: source)
      events = []

      count = consumer.start { |event| events << event }

      assert_equal 2, count
      assert_equal source, events
    end

    def test_start_returns_enumerator_without_block
      consumer = ReplicationConsumer.new(source: [sample_event("0/1")])

      assert_instance_of Enumerator, consumer.start
    end

    def test_start_flattens_transaction_envelopes_inside_arrays
      events = [sample_event("0/1"), sample_event("0/2")]
      envelope = FakeEnvelope.new(events, "tx-1")
      consumer = ReplicationConsumer.new(source: [[envelope]])
      consumed = []

      count = consumer.start { |event| consumed << event }

      assert_equal 2, count
      assert_equal events, consumed
    end

    def test_start_returns_empty_count_for_nil_source_items
      consumer = ReplicationConsumer.new(source: [nil])

      assert_equal(0, consumer.start { |_event| flunk "nil work should not yield events" })
    end

    def test_start_flattens_transaction_envelope_inside_array_with_plain_event
      envelope = FakeEnvelope.new([sample_event("0/10"), sample_event("0/11")], "tx-2")
      consumer = ReplicationConsumer.new(source: [[envelope, sample_event("0/12")]])
      events = []

      count = consumer.start { |event| events << event }

      assert_equal 3, count
      assert_equal(%w[0/10 0/11 0/12], events.map { |event| event.fetch("source_position") })
    end

    def test_start_preserves_transaction_envelope_when_delivery_unit_is_transaction
      events = [sample_event("0/1"), sample_event("0/2")]
      envelope = FakeEnvelope.new(events, "tx-1")
      consumer = ReplicationConsumer.new(source: [envelope], delivery_unit: :transaction)
      consumed = []

      count = consumer.start { |work| consumed << work }

      assert_equal 1, count
      assert_equal [envelope], consumed
    end

    def test_transaction_delivery_wraps_plain_hash_event_without_to_h_conversion
      event = {
        "operation" => "insert",
        "source_position" => "0/plain",
        "event_id" => "event-plain",
        "occurred_at" => "2026-01-01T00:00:00Z"
      }
      consumer = ReplicationConsumer.new(source: [event], delivery_unit: :transaction)
      consumed = []

      assert_equal(1, consumer.start { |work| consumed << work })
      envelope = consumed.fetch(0)
      assert_equal [event], envelope.events
      assert_equal "event-plain", envelope.transaction_id
      assert_equal "0/plain", envelope.commit_lsn
    end

    def test_start_rejects_non_cdc_work
      consumer = ReplicationConsumer.new(source: [:not_cdc])

      error = assert_raises(ReplicationError) { consumer.start {} }

      assert_match(/non-CDC work: Symbol/, error.message)
    end

    def test_start_rejects_hash_without_cdc_position
      consumer = ReplicationConsumer.new(source: [{ "operation" => "insert" }])

      error = assert_raises(ReplicationError) { consumer.start {} }

      assert_match(/non-CDC work: Hash/, error.message)
    end

    def test_start_accepts_symbol_keyed_cdc_events
      event = { operation: "insert", commit_lsn: "0/20" }
      consumer = ReplicationConsumer.new(source: [event])
      events = []

      assert_equal(1, consumer.start { |consumed| events << consumed })
      assert_equal [event], events
    end

    def test_start_rejects_to_h_without_key_protocol
      event = Object.new
      def event.to_h = Object.new
      consumer = ReplicationConsumer.new(source: [event])

      error = assert_raises(ReplicationError) { consumer.start {} }

      assert_match(/non-CDC work/, error.message)
    end

    FakeEnvelope = Data.define(:events, :transaction_id)

    private

    def sample_event(position)
      { "operation" => "insert", "source_position" => position }
    end
  end
end
