# frozen_string_literal: true

require "test_helper"

module Mammoth
  # rubocop:disable Metrics/ClassLength
  class PgoutputSourceTest < Minitest::Test
    def test_streams_payloads_through_pgoutput_and_cdc_components
      config = Configuration.load(fixture_config_path)
      runner = FakeRunner.new([["payload", FakeMetadata.new("0/1")]])
      parser = ->(payload) { "parsed-#{payload}" }
      decoder = ->(parsed, metadata) { { decoded: parsed, lsn: metadata.wal_end_lsn } }
      source_adapter = FakeSourceAdapter.new
      source = PgoutputSource.new(
        config,
        runner: runner,
        parser: parser,
        decoder: decoder,
        source_adapter: source_adapter
      )
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

      error = assert_raises(ReplicationError) do
        source.stub(:require_optional!, ->(_feature, gem_name) { raise ReplicationError, "#{gem_name} is required" }) do
          source.each.first
        end
      end

      assert_match(/pgoutput-client is required/, error.message)
    end

    def test_wraps_unexpected_runner_errors_as_replication_errors
      config = Configuration.load(fixture_config_path)
      runner = Object.new
      def runner.start
        raise "socket exploded"
      end
      source = PgoutputSource.new(config, runner: runner, source_adapter: FakeSourceAdapter.new)

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/pgoutput replication failed: socket exploded/, error.message)
    end

    def test_each_returns_enumerator_without_block
      source = PgoutputSource.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new([]),
        source_adapter: FakeSourceAdapter.new
      )

      assert_instance_of Enumerator, source.each
    end

    def test_streams_without_parser_or_decoder_when_components_are_not_injected
      config = Configuration.load(fixture_config_path)
      runner = FakeRunner.new([[{ lsn: "0/2" }, FakeMetadata.new("0/2")]])
      source_adapter = CallableSourceAdapter.new
      source = PgoutputSource.new(config, runner: runner, source_adapter: source_adapter)

      events = source.each.to_a

      assert_equal 1, events.size
      assert_equal "0/2", events.first.fetch("source_position")
    end

    def test_raises_when_source_adapter_has_no_supported_interface
      config = Configuration.load(fixture_config_path)
      source = PgoutputSource.new(
        config,
        runner: FakeRunner.new([["payload", FakeMetadata.new("0/3")]]),
        source_adapter: Object.new
      )

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/source adapter must respond/, error.message)
    end

    def test_raises_when_parser_component_has_no_supported_interface
      config = Configuration.load(fixture_config_path)
      source = PgoutputSource.new(
        config,
        runner: FakeRunner.new([["payload", FakeMetadata.new("0/4")]]),
        parser: Object.new,
        source_adapter: FakeSourceAdapter.new
      )

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/must respond to #call, #parse, or #decode/, error.message)
    end

    def test_parser_component_can_use_parse_interface
      config = Configuration.load(fixture_config_path)
      parser = Object.new
      def parser.parse(payload)
        "parsed-#{payload}"
      end
      decoder = ->(parsed, metadata) { { decoded: parsed, lsn: metadata.wal_end_lsn } }
      source = PgoutputSource.new(
        config,
        runner: FakeRunner.new([["payload", FakeMetadata.new("0/5")]]),
        parser: parser,
        decoder: decoder,
        source_adapter: FakeSourceAdapter.new
      )

      event = source.each.first

      assert_equal "0/5", event.fetch("source_position")
    end

    def test_decoder_component_can_use_decode_interface
      config = Configuration.load(fixture_config_path)
      decoder = Object.new
      def decoder.decode(parsed, metadata)
        { decoded: parsed, lsn: metadata.wal_end_lsn }
      end
      source = PgoutputSource.new(
        config,
        runner: FakeRunner.new([["payload", FakeMetadata.new("0/6")]]),
        decoder: decoder,
        source_adapter: FakeSourceAdapter.new
      )

      event = source.each.first

      assert_equal "0/6", event.fetch("source_position")
    end

    def test_private_helpers_cover_live_dependency_edges
      config = Configuration.load(fixture_config_path)
      source = PgoutputSource.new(config)

      assert source.send(:require_any!, ["json"], "json")

      error = assert_raises(ReplicationError) do
        source.send(:require_any!, %w[mammoth_missing_feature_a mammoth_missing_feature_b], "missing-gem")
      end
      assert_match(/missing-gem is required/, error.message)
      assert_same Configuration, source.send(:constant_or_nil, "Mammoth::Configuration")
      assert_nil source.send(:constant_or_nil, "Mammoth::Missing::Constant")
    end

    def test_database_url_uses_configured_postgres_fields_and_password_env
      config = Configuration.load(fixture_config_path)
      source = PgoutputSource.new(config)

      ENV.stub(:fetch, "secret") do
        url = source.send(:database_url)

        assert_match(%r{\Apostgres://mammoth:secret@localhost:5432/app_development\z}, url)
      end
    end

    def test_build_source_adapter_reports_missing_adapter_constant
      config = Configuration.load(fixture_config_path)
      source = PgoutputSource.new(config)

      source.stub(:require_optional!, true) do
        source.stub(:require_any!, true) do
          source.stub(:constant_or_nil, nil) do
            error = assert_raises(ReplicationError) { source.send(:build_source_adapter) }

            assert_match(/Pgoutput::SourceAdapter::Cdc is unavailable/, error.message)
          end
        end
      end
    end

    def test_normalize_source_positions_supports_symbols_and_non_hash_items
      config = Configuration.load(fixture_config_path)
      source = PgoutputSource.new(config)
      object = Object.new

      normalized = source.send(
        :normalize_source_positions,
        [{ operation: "insert", commit_lsn: "0/SYMBOL" }, object]
      )

      assert_equal "0/SYMBOL", normalized.first.fetch("source_position")
      assert_same object, normalized.last
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

    class CallableSourceAdapter
      def call(decoded, _metadata)
        {
          "operation" => "insert",
          "schema" => "public",
          "table" => "orders",
          "commit_lsn" => decoded.fetch(:lsn),
          "new_values" => { "id" => 1 }
        }
      end
    end

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
  # rubocop:enable Metrics/ClassLength
end
