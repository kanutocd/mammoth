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

      def test_enrich_work_position_handles_symbol_keyed_and_existing_positions
        source = Postgres.new(Configuration.load(fixture_config_path))

        enriched = source.send(:enrich_work_position, { operation: "insert" }, { lsn: "0/symbol" }, Object.new)
        existing = source.send(:enrich_work_position, { operation: "insert", source_position: "0/existing" }, { lsn: "0/new" }, Object.new)

        assert_equal "0/symbol", enriched.fetch(:source_position)
        assert_equal "0/symbol", enriched.fetch(:commit_lsn)
        assert_equal "0/existing", existing.fetch(:source_position)
        refute_equal "0/new", existing.fetch(:source_position)
      end

      def test_value_from_handles_nil_plain_objects_and_string_keys
        source = Postgres.new(Configuration.load(fixture_config_path))

        assert_nil source.send(:value_from, nil, :missing)
        assert_nil source.send(:value_from, Object.new, :missing)
        assert_equal "value", source.send(:value_from, { "answer" => "value" }, :answer)
      end

      FakeCommit = Data.define(:commit_lsn)
    end
  end
end
