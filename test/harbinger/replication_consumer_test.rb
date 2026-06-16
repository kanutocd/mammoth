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
  end
end
