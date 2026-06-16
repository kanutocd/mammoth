# frozen_string_literal: true

require "test_helper"

module Mammoth
  class PgoutputSourceTest < Minitest::Test
    def test_streams_payloads_through_pgoutput_and_cdc_components
      config = Configuration.load(fixture_config_path)
      runner = FakeRunner.new([["payload", FakeMetadata.new("0/1")]])
      parser = ->(payload) { "parsed-#{payload}" }
      decoder = ->(parsed, metadata) { { decoded: parsed, lsn: metadata.wal_end_lsn } }
      source_adapter = FakeSourceAdapter.new
      source = PgoutputSource.new(config, runner: runner, parser: parser, decoder: decoder, source_adapter: source_adapter)
      events = []

      source.each { |event| events << event }

      assert_equal 1, events.size
      assert_equal "insert", events.first.fetch("operation")
      assert_equal "0/1", events.first.fetch("source_position")
      assert_equal [["payload", "0/1"]], runner.started
    end

    def test_requires_live_pgoutput_dependencies_when_runner_is_not_injected
      config = Configuration.load(fixture_config_path)
      source = PgoutputSource.new(config)

      error = assert_raises(ReplicationError) { source.each.first }

      assert_match(/pgoutput-client is required|Pgoutput::SourceAdapter::Cdc is unavailable/, error.message)
    end

    class FakeRunner
      attr_reader :started

      def initialize(items)
        @items = items
        @started = []
      end

      def start
        @items.each do |payload, metadata|
          @started << [payload, metadata.wal_end_lsn]
          yield payload, metadata
        end
      end
    end

    FakeMetadata = Data.define(:wal_end_lsn)

    class FakeSourceAdapter
      def normalize(decoded)
        {
          "operation" => "insert",
          "schema" => "public",
          "table" => "orders",
          "commit_lsn" => decoded.fetch(:lsn),
          "new_values" => { "id" => 1 }
        }
      end
    end
  end
end
