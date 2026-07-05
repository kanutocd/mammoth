# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Sources
    class PostgresBranchEdgesTest < Minitest::Test
      def test_normalize_decoded_handles_nil_and_nested_arrays
        source = Postgres.new(
          Configuration.load(fixture_config_path),
          adapter: ->(decoded) { decoded }
        )

        assert_equal [], source.send(:normalize_decoded, nil)
        assert_equal [{ "operation" => "insert" }], source.send(:normalize_decoded, [[nil, { "operation" => "insert" }]])
      end

      def test_emit_transaction_buffer_without_active_buffer_is_noop
        source = Postgres.new(Configuration.load(fixture_config_path))
        emitted = []

        source.send(:emit_transaction_buffer, FakeCommit.new("0/10"), nil) { |work| emitted << work }

        assert_empty emitted
      end

      def test_transaction_envelope_falls_back_to_first_event_values
        source = Postgres.new(Configuration.load(fixture_config_path))
        emitted = []

        source.send(:start_transaction_buffer, Object.new)
        source.instance_variable_get(:@transaction_events) << { transaction_id: "tx-from-event", commit_lsn: "0/event" }
        source.send(:emit_transaction_buffer, Object.new, nil) { |work| emitted << work }

        envelope = emitted.fetch(0)
        assert_equal "tx-from-event", envelope.transaction_id
        assert_equal "0/event", envelope.commit_lsn
      end

      def test_start_transaction_buffer_keeps_hash_metadata
        source = Postgres.new(Configuration.load(fixture_config_path))
        source.send(:start_transaction_buffer, { metadata: { "origin" => "test" } })
        emitted = []

        source.send(:emit_transaction_buffer, FakeCommit.new("0/11"), nil) { |work| emitted << work }

        assert_equal({ "origin" => "test" }, emitted.fetch(0).metadata)
      end

      def test_enrich_work_position_noops_without_position_or_hash_shape
        source = Postgres.new(Configuration.load(fixture_config_path))
        object = Object.new

        assert_same object, source.send(:enrich_work_position, object, nil, nil)
        assert_equal({ operation: "insert" }, source.send(:enrich_work_position, { operation: "insert" }, nil, nil))
      end

      def test_enrich_work_position_noops_for_non_hash_work_with_metadata_position
        source = Postgres.new(Configuration.load(fixture_config_path))
        object = Object.new

        assert_same object, source.send(:enrich_work_position, object, { lsn: "0/metadata" }, nil)
      end

      def test_enrich_work_position_handles_symbol_keyed_and_existing_positions
        source = Postgres.new(Configuration.load(fixture_config_path))

        enriched = source.send(:enrich_work_position, { operation: "insert" }, { lsn: "0/symbol" }, Object.new)
        existing = source.send(:enrich_work_position, { operation: "insert", source_position: "0/existing" }, { lsn: "0/new" },
                               Object.new)

        assert_equal "0/symbol", enriched.fetch(:source_position)
        assert_equal "0/symbol", enriched.fetch(:commit_lsn)
        assert_equal "0/existing", existing.fetch(:source_position)
        refute_equal "0/new", existing.fetch(:source_position)
      end

      def test_enrich_work_position_uses_decoded_position_for_string_keyed_work
        source = Postgres.new(Configuration.load(fixture_config_path))
        decoded = { "source_position" => "0/decoded" }

        enriched = source.send(:enrich_work_position, { "operation" => "insert" }, nil, decoded)

        assert_equal "0/decoded", enriched.fetch("source_position")
        assert_equal "0/decoded", enriched.fetch("commit_lsn")
      end

      def test_enrich_work_position_preserves_existing_string_keyed_position
        source = Postgres.new(Configuration.load(fixture_config_path))
        work = { "operation" => "insert", "commit_lsn" => "0/existing" }

        enriched = source.send(:enrich_work_position, work, { lsn: "0/new" }, Object.new)

        assert_same work, enriched
        assert_equal "0/existing", enriched.fetch("commit_lsn")
      end

      def test_value_from_handles_nil_plain_objects_and_string_keys
        source = Postgres.new(Configuration.load(fixture_config_path))

        assert_nil source.send(:value_from, nil, :missing)
        assert_nil source.send(:value_from, Object.new, :missing)
        assert_equal "value", source.send(:value_from, { "answer" => "value" }, :answer)
      end

      def test_decode_message_call_interface_without_metadata
        decoder = ->(message) { "decoded-#{message}" }
        source = Postgres.new(Configuration.load(fixture_config_path), decoder: decoder)

        assert_equal "decoded-payload", source.send(:decode_message, "payload", { lsn: "0/1" })
      end

      def test_process_decoded_skips_nil_normalized_work_outside_transaction
        source = Postgres.new(Configuration.load(fixture_config_path), adapter: ->(_decoded) { nil })
        emitted = []

        source.send(:process_decoded, "row", nil) { |work| emitted << work }

        assert_empty emitted
      end

      def test_process_decoded_skips_nil_work_from_mixed_adapter_result
        source = Postgres.new(
          Configuration.load(fixture_config_path),
          adapter: ->(_decoded) { [nil, { "operation" => "insert", "source_position" => "0/mixed" }] }
        )
        emitted = []

        source.send(:process_decoded, "row", nil) { |work| emitted << work }

        assert_equal [{ "operation" => "insert", "source_position" => "0/mixed" }], emitted
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

      FakeCommit = Data.define(:commit_lsn)
    end
  end
end
