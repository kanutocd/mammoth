# frozen_string_literal: true

require "test_helper"

module Mammoth
  class ReplicationConsumerTest < Minitest::Test
    def test_exposes_replication_configuration
      consumer = ReplicationConsumer.new(Configuration.load(fixture_config_path))

      assert_equal "mammoth_prod", consumer.slot
      assert_equal "mammoth_publication", consumer.publication
    end

    def test_start_raises_until_pgoutput_source_is_configured
      consumer = ReplicationConsumer.new(Configuration.load(fixture_config_path))

      error = assert_raises(ReplicationError) { consumer.start {} }

      assert_match(/source is not configured/, error.message)
    end

    def test_start_yields_injected_source_events
      source = [{ operation: "insert" }, { operation: "update" }]
      consumer = ReplicationConsumer.new(Configuration.load(fixture_config_path), source: source)
      events = []

      count = consumer.start { |event| events << event }

      assert_equal 2, count
      assert_equal source, events
    end

    def test_start_normalizes_events_with_adapter
      source = [{ operation: "insert" }]
      adapter = ->(event) { event.merge(normalized: true) }
      consumer = ReplicationConsumer.new(Configuration.load(fixture_config_path), source: source, adapter: adapter)
      events = []

      consumer.start { |event| events << event }

      assert events.first.fetch(:normalized)
    end

    def test_start_returns_enumerator_without_block
      source = [{ operation: "insert" }]
      consumer = ReplicationConsumer.new(Configuration.load(fixture_config_path), source: source)

      assert_instance_of Enumerator, consumer.start
    end

    def test_start_flattens_transaction_envelopes_inside_arrays
      events = [{ operation: "insert" }, { operation: "update" }]
      envelope = FakeEnvelope.new(events, "tx-1")
      consumer = ReplicationConsumer.new(Configuration.load(fixture_config_path), source: [[envelope]])
      consumed = []

      count = consumer.start { |event| consumed << event }

      assert_equal 2, count
      assert_equal events, consumed
    end

    def test_start_returns_empty_count_for_nil_source_items
      consumer = ReplicationConsumer.new(Configuration.load(fixture_config_path), source: [nil])

      assert_equal(0, consumer.start { |_event| flunk "nil work should not yield events" })
    end

    def test_start_skips_nil_adapter_results
      config = Configuration.load(fixture_config_path)
      consumer = ReplicationConsumer.new(config, source: [:ignored], adapter: ->(_event) {})
      events = []

      count = consumer.start { |event| events << event }

      assert_equal 0, count
      assert_empty events
    end

    def test_start_flattens_transaction_envelope_inside_array_with_plain_event
      config = Configuration.load(fixture_config_path)
      envelope = FakeEnvelope.new([sample_event("0/10"), sample_event("0/11")], "tx-2")
      consumer = ReplicationConsumer.new(config, source: [[envelope, sample_event("0/12")]])
      events = []

      count = consumer.start { |event| events << event }

      assert_equal 3, count
      assert_equal(["0/10", "0/11", "0/12"], events.map { |event| event.fetch("source_position") })
    end

    FakeEnvelope = Data.define(:events, :transaction_id)

    private

    def sample_event(position)
      { "operation" => "insert", "source_position" => position }
    end
  end
end
