# frozen_string_literal: true

require "test_helper"

module Mammoth
  class ReplicationConsumerTest < Minitest::Test
    def test_start_raises_until_cdc_source_is_configured
      error = assert_raises(ReplicationError) { ReplicationConsumer.new.start {} }

      assert_match(/source is not configured/, error.message)
    end

    def test_start_yields_exact_core_events
      source = [core_event(source_position: "0/1"), core_event(source_position: "0/2")]
      events = ReplicationConsumer.new(source: source).start.to_a

      assert_equal source, events
      assert(events.all? { |event| event.is_a?(CDC::Core::ChangeEvent) })
    end

    def test_start_returns_enumerator_without_block
      consumer = ReplicationConsumer.new(source: [core_event])

      assert_instance_of Enumerator, consumer.start
    end

    def test_start_flattens_exact_core_transaction_envelopes_inside_arrays
      events = [core_event(source_position: "0/1"), core_event(source_position: "0/2")]
      envelope = core_envelope(events: events)
      consumed = ReplicationConsumer.new(source: [[envelope]]).start.to_a

      assert_equal events, consumed
    end

    def test_start_returns_empty_count_for_nil_source_items
      consumer = ReplicationConsumer.new(source: [nil])

      assert_equal(0, consumer.start { |_event| flunk "nil work should not yield events" })
    end

    def test_start_flattens_mixed_core_work
      envelope = core_envelope(
        events: [core_event(source_position: "0/10"), core_event(source_position: "0/11")]
      )
      standalone = core_event(source_position: "0/12")
      consumed = ReplicationConsumer.new(source: [[envelope, standalone]]).start.to_a

      assert_equal %w[0/10 0/11 0/12], consumed.map(&:commit_lsn)
    end

    def test_start_preserves_exact_core_envelope_for_transaction_delivery
      envelope = core_envelope(events: [core_event, core_event(source_position: "0/2")])
      consumed = ReplicationConsumer.new(source: [envelope], delivery_unit: :transaction).start.to_a

      assert_equal [envelope], consumed
      assert_instance_of CDC::Core::TransactionEnvelope, consumed.fetch(0)
    end

    def test_transaction_delivery_wraps_core_event_in_core_envelope
      occurred_at = Time.utc(2026, 1, 1)
      event = core_event(
        event_id: "event-plain",
        source_position: "0/plain",
        transaction_id: "tx-plain",
        occurred_at: occurred_at
      )
      envelope = ReplicationConsumer.new(source: [event], delivery_unit: :transaction).start.to_a.fetch(0)

      assert_instance_of CDC::Core::TransactionEnvelope, envelope
      assert_equal [event], envelope.events
      assert_equal "tx-plain", envelope.transaction_id
      assert_equal "0/plain", envelope.commit_lsn
      assert_equal occurred_at, envelope.committed_at
    end

    def test_transaction_delivery_uses_core_metadata_identity_when_transaction_id_is_absent
      event = core_event(event_id: "event-identity", transaction_id: nil)
      envelope = ReplicationConsumer.new(source: [event], delivery_unit: :transaction).start.to_a.fetch(0)

      assert_equal "event-identity", envelope.transaction_id
      assert_same event.metadata, envelope.metadata
    end

    def test_start_rejects_non_core_work
      error = assert_raises(ReplicationError) { ReplicationConsumer.new(source: [{ operation: :insert }]).start {} }

      assert_match(/non-core work: Hash/, error.message)
    end
  end
end
