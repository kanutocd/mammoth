# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Sources
    class PostgresBranchEdgesTest < Minitest::Test
      def test_each_decoded_handles_nil_nested_arrays_and_scalar_values
        source = Postgres.new(Configuration.load(fixture_config_path))
        emitted = []

        source.send(:each_decoded, nil) { |decoded| emitted << decoded }
        source.send(:each_decoded, [[nil, "row-1"], "row-2"]) { |decoded| emitted << decoded }

        assert_equal %w[row-1 row-2], emitted
      end

      def test_stream_event_preserves_decoded_value_without_context_factory
        adapter = BareStreamingAdapter.new
        source = Postgres.new(Configuration.load(fixture_config_path), adapter: adapter)

        assert_equal "row", source.send(:stream_event, "row", { lsn: "0/1" })
      end

      def test_stream_event_passes_nil_position_to_context_factory
        adapter = ContextStreamingAdapter.new
        source = Postgres.new(Configuration.load(fixture_config_path), adapter: adapter)

        assert_equal ["row", nil], source.send(:stream_event, "row", nil)
      end

      def test_value_from_handles_nil_plain_objects_string_keys_and_late_keys
        source = Postgres.new(Configuration.load(fixture_config_path))

        assert_nil source.send(:value_from, nil, :missing)
        assert_nil source.send(:value_from, Object.new, :missing)
        assert_equal "value", source.send(:value_from, { "answer" => "value" }, :missing, :answer)
      end

      def test_decode_message_call_interface_without_metadata
        decoder = ->(message) { "decoded-#{message}" }
        source = Postgres.new(Configuration.load(fixture_config_path), decoder: decoder)

        assert_equal "decoded-payload", source.send(:decode_message, "payload", { lsn: "0/1" })
      end

      def test_decode_message_reports_unsupported_decoder_interface
        source = Postgres.new(Configuration.load(fixture_config_path), decoder: Object.new)

        error = assert_raises(ReplicationError) { source.send(:decode_message, "payload", nil) }

        assert_match(/pgoutput decoder must respond/, error.message)
      end

      def test_default_pgoutput_component_builders_are_memoized
        source = Postgres.new(Configuration.load(fixture_config_path))

        assert_same source.send(:effective_parser), source.send(:effective_parser)
        assert_same source.send(:effective_decoder), source.send(:effective_decoder)
        assert_same source.send(:effective_adapter), source.send(:effective_adapter)
        assert_same source.send(:effective_runner), source.send(:effective_runner)
      end

      def test_require_optional_reports_missing_feature
        source = Postgres.new(Configuration.load(fixture_config_path))

        error = assert_raises(ReplicationError) do
          source.send(:require_optional!, "mammoth/missing/coverage_feature", "missing-gem")
        end

        assert_match(/missing-gem is required/, error.message)
      end

      def test_checkpoint_lsn_is_nil_when_checkpoint_row_is_missing
        with_temp_dir do |dir|
          config = Configuration.load(fixture_config_path)
          config.data.fetch("sqlite")["path"] = File.join(dir, "mammoth.db")
          store = SQLiteStore.connect(config.dig("sqlite", "path")).bootstrap!
          source = Postgres.new(config, checkpoint_store: CheckpointStore.new(store))

          assert_nil source.send(:checkpoint_lsn)
        end
      end

      def test_normalize_lsn_handles_blank_already_formatted_and_non_numeric_values
        source = Postgres.new(Configuration.load(fixture_config_path))

        assert_nil source.send(:normalize_lsn, "")
        assert_equal "0/ABC", source.send(:normalize_lsn, "0/ABC")
        assert_equal "not-a-number", source.send(:normalize_lsn, "not-a-number")
      end

      class BareStreamingAdapter
        def each_normalized(events, &block)
          events.each(&block)
        end
      end

      class ContextStreamingAdapter < BareStreamingAdapter
        def stream_event(event, source_position: nil)
          [event, source_position]
        end
      end
    end
  end
end
