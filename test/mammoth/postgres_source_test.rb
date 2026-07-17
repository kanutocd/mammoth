# frozen_string_literal: true

require "test_helper"
require "cdc/core"
require "pgoutput/decoder/events"
require "pgoutput/source_adapter"

module Mammoth
  # rubocop:disable Metrics/ClassLength
  class PostgresSourceTest < Minitest::Test
    def test_streams_from_injected_cdc_source_components
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload-1"]),
        parser: ->(payload) { "parsed-#{payload}" },
        decoder: ->(message) { "decoded-#{message}" },
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      events = source.each.to_a
      assert_equal ["decoded-parsed-payload-1"], events.map(&:commit_lsn)
      assert(events.all? { |event| event.is_a?(CDC::Core::ChangeEvent) })
    end

    def test_each_returns_enumerator_without_block
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new([]),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      assert_instance_of Enumerator, source.each
    end

    def test_parser_can_use_parse_interface
      parser = Object.new
      def parser.parse(payload) = "parsed-#{payload}"
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: parser,
        decoder: ->(message) { message },
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      assert_equal "parsed-payload", source.each.first.commit_lsn
    end

    def test_decoder_can_use_decode_interface
      decoder = Object.new
      def decoder.decode(message) = "decoded-#{message}"
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: decoder,
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      assert_equal "decoded-payload", source.each.first.commit_lsn
    end

    def test_adapter_can_use_streaming_normalization_interface
      adapter = streaming_adapter { |decoded| sample_event(decoded) }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: adapter
      )

      assert_equal "payload", source.each.first.commit_lsn
    end

    def test_ignores_nil_decoded_messages
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: ->(_message) { nil },
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      assert_equal [], source.each.to_a
    end

    def test_parser_can_use_process_interface
      parser = Object.new
      def parser.process(payload) = "processed-#{payload}"
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: parser,
        decoder: ->(message) { message },
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      assert_equal "processed-payload", source.each.first.commit_lsn
    end

    def test_decoder_decode_interface_can_receive_metadata
      decoder = Object.new
      def decoder.decode(message, metadata) = "#{message}-#{metadata.fetch(:lsn)}"
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunnerWithMetadata.new([["payload", { lsn: "0/42" }]]),
        parser: ->(payload) { payload },
        decoder: decoder,
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      assert_equal "payload-0/42", source.each.first.commit_lsn
    end

    def test_decoder_call_interface_can_receive_metadata
      decoder = ->(message, metadata) { "#{message}-#{metadata.fetch(:lsn)}" }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunnerWithMetadata.new([["payload", { lsn: "0/43" }]]),
        parser: ->(payload) { payload },
        decoder: decoder,
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      assert_equal "payload-0/43", source.each.first.commit_lsn
    end

    def test_adapter_can_return_array_of_work
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: streaming_adapter { |decoded| [nil, sample_event(decoded)] }
      )

      events = source.each.to_a
      assert_equal ["payload"], events.map(&:commit_lsn)
      assert_instance_of CDC::Core::ChangeEvent, events.fetch(0)
    end

    def test_reports_adapter_with_no_supported_interface
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: Object.new
      )

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/source adapter must respond/, error.message)
    end

    def test_delegates_transaction_normalization_to_source_adapter
      decoded_messages = %w[begin row-1 row-2 commit]
      event = CDC::Core::ChangeEvent.new(operation: :insert, schema: "public", table: "orders")
      envelope = CDC::Core::TransactionEnvelope.new(
        transaction_id: "tx-1", events: [event], commit_lsn: "0/99"
      )
      adapter = RecordingStreamingAdapter.new(envelope)
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(decoded_messages),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: adapter
      )

      assert_same envelope, source.each.first
      assert_equal decoded_messages, adapter.inputs.map(&:event)
    end

    # rubocop:disable Metrics/MethodLength
    def test_streams_exact_core_transaction_envelope_from_pgoutput_adapter
      events = Pgoutput::Decoder::Events
      decoded_messages = {
        "begin" => events::Begin.new(42, 10, 123_456),
        "row" => events::Insert.new(42, 7, "public", "orders", { "id" => 1 }),
        "commit" => events::Commit.new(42, 0, 11, 12, 123_789)
      }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunnerWithMetadata.new([
                                             ["begin", { lsn: "0/begin" }],
                                             ["row", { lsn: "0/row" }],
                                             ["commit", { lsn: "0/commit" }]
                                           ]),
        parser: ->(payload) { payload },
        decoder: ->(message, _metadata) { decoded_messages.fetch(message) },
        adapter: Pgoutput::SourceAdapter::Cdc.new
      )

      envelope = source.each.first

      assert_instance_of CDC::Core::TransactionEnvelope, envelope
      assert_equal "11", envelope.commit_lsn
      assert_instance_of CDC::Core::ChangeEvent, envelope.events.first
      assert_equal "0/row", envelope.events.first.commit_lsn
    end
    # rubocop:enable Metrics/MethodLength

    def test_forwards_transport_positions_to_source_adapter
      adapter = streaming_adapter { |_decoded, position| sample_event(position) }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunnerWithMetadata.new([
                                             ["row-1", { lsn: "0/1" }],
                                             ["row-2", WalMetadata.new("0/2")]
                                           ]),
        parser: ->(payload) { payload },
        decoder: ->(message, _metadata) { message },
        adapter: adapter
      )

      assert_equal(%w[0/1 0/2], source.each.map(&:commit_lsn))
      assert_equal %w[0/1 0/2], adapter.inputs.map(&:source_position)
    end

    def test_decoder_can_emit_array_of_decoded_messages
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: ->(_message) { ["row-1", nil, "row-2"] },
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      assert_equal(%w[row-1 row-2], source.each.map(&:commit_lsn))
    end

    def test_adapter_without_stream_event_receives_decoded_values
      adapter = BareStreamingAdapter.new
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["row"]),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: adapter
      )

      assert_equal ["row"], source.each.to_a
    end

    def test_database_url_includes_password_when_present
      source = Sources::Postgres.new(Configuration.load(fixture_config_path))

      original_password = ENV["MAMMOTH_POSTGRES_PASSWORD"]
      ENV["MAMMOTH_POSTGRES_PASSWORD"] = "secret"

      assert_match(%r{postgres://mammoth:secret@localhost:5432/app_development}, source.send(:database_url))
    ensure
      ENV["MAMMOTH_POSTGRES_PASSWORD"] = original_password
    end

    def test_reports_missing_required_postgres_config
      config = Configuration.load(fixture_config_path)
      config.data.fetch("postgres").delete("host")
      source = Sources::Postgres.new(config)

      error = assert_raises(ReplicationError) { source.send(:database_url) }

      assert_match(/postgres.host/, error.message)
    end

    def test_uses_plural_publication_names_from_configuration
      source = Sources::Postgres.new(Configuration.load(fixture_config_path))

      assert_equal ["mammoth_publication"], source.send(:required_publications)
    end

    def test_runner_options_include_optional_transport_lifecycle_settings
      config = Configuration.load(fixture_config_path)
      config.data.fetch("replication")["auto_create_slot"] = true
      config.data.fetch("replication")["temporary_slot"] = true
      config.data.fetch("replication")["feedback_interval"] = 7.5
      source = Sources::Postgres.new(config)

      options = source.send(:runner_options)

      assert options.fetch(:auto_create_slot)
      assert options.fetch(:temporary_slot)
      assert_equal 7.5, options.fetch(:feedback_interval)
    end

    def test_runner_options_preserve_false_transport_lifecycle_settings
      config = Configuration.load(fixture_config_path)
      config.data.fetch("replication")["auto_create_slot"] = false
      config.data.fetch("replication")["temporary_slot"] = false
      source = Sources::Postgres.new(config)

      options = source.send(:runner_options)

      refute options.fetch(:auto_create_slot)
      refute options.fetch(:temporary_slot)
    end

    def test_runner_options_omit_feedback_interval_when_not_configured
      config = Configuration.load(fixture_config_path)
      config.data.fetch("replication").delete("feedback_interval")
      source = Sources::Postgres.new(config)

      refute_includes source.send(:runner_options), :feedback_interval
    end

    def test_runner_options_resume_from_persisted_checkpoint_when_start_lsn_is_not_configured
      with_temp_dir do |dir|
        config = Configuration.load(fixture_config_path)
        config.data.fetch("sqlite")["path"] = File.join(dir, "mammoth.db")
        config.data.fetch("replication").delete("start_lsn")
        store = SQLiteStore.connect(config.dig("sqlite", "path")).bootstrap!
        checkpoint_store = CheckpointStore.new(store)
        checkpoint_store.write(
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          last_lsn: "26622536"
        )
        source = Sources::Postgres.new(config, checkpoint_store: checkpoint_store)

        assert_equal "0/1963A48", source.send(:runner_options).fetch(:start_lsn)
      end
    end

    def test_runner_options_prefer_explicit_start_lsn_over_persisted_checkpoint
      with_temp_dir do |dir|
        config = Configuration.load(fixture_config_path)
        config.data.fetch("sqlite")["path"] = File.join(dir, "mammoth.db")
        config.data.fetch("replication")["start_lsn"] = "0/CONFIG"
        store = SQLiteStore.connect(config.dig("sqlite", "path")).bootstrap!
        checkpoint_store = CheckpointStore.new(store)
        checkpoint_store.write(
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          last_lsn: "0/CHECKPOINT"
        )
        source = Sources::Postgres.new(config, checkpoint_store: checkpoint_store)

        assert_equal "0/CONFIG", source.send(:runner_options).fetch(:start_lsn)
      end
    end

    def test_runner_options_do_not_resume_without_checkpoint
      config = Configuration.load(fixture_config_path)
      config.data.fetch("replication").delete("start_lsn")
      source = Sources::Postgres.new(config)

      assert_nil source.send(:runner_options).fetch(:start_lsn)
    end

    def test_rejects_empty_publications
      config = Configuration.load(fixture_config_path)
      config.data.fetch("replication")["publications"] = []
      source = Sources::Postgres.new(config)

      error = assert_raises(ReplicationError) { source.send(:required_publications) }

      assert_match(/replication.publications/, error.message)
    end

    def test_reports_parser_with_no_supported_interface
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: Object.new,
        decoder: ->(message) { message },
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/pgoutput parser must respond/, error.message)
    end

    def test_reports_missing_default_pgoutput_client
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      source.stub(:require_optional!, ->(_feature, gem_name) { raise ReplicationError, "#{gem_name} missing" }) do
        error = assert_raises(ReplicationError) { source.each.to_a }

        assert_match(/pgoutput-client missing/, error.message)
      end
    end

    def test_wraps_unexpected_source_errors
      broken_runner = Object.new
      def broken_runner.start
        raise "stream exploded"
      end
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: broken_runner,
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: streaming_adapter { |decoded| sample_event(decoded) }
      )

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/PostgreSQL CDC source failed: stream exploded/, error.message)
    end

    StreamInput = Data.define(:event, :source_position)
    WalMetadata = Data.define(:wal_end_lsn)

    class StreamingAdapter
      attr_reader :normalizer, :inputs

      def initialize(normalizer)
        @normalizer = normalizer
        @inputs = []
      end

      def stream_event(event, source_position: nil)
        StreamInput.new(event, source_position)
      end

      def each_normalized(events, &block)
        return enum_for(:each_normalized, events) unless block_given?

        events.each do |input|
          inputs << input
          result = if normalizer.arity == 1
                     normalizer.call(input.event)
                   else
                     normalizer.call(input.event, input.source_position)
                   end
          works = result.is_a?(Array) ? result : [result]
          works.compact.each(&block)
        end
        nil
      end
    end

    class RecordingStreamingAdapter
      attr_reader :output, :inputs

      def initialize(output)
        @output = output
        @inputs = []
      end

      def stream_event(event, source_position: nil)
        StreamInput.new(event, source_position)
      end

      def each_normalized(events)
        @inputs = events.to_a
        yield output
      end
    end

    class BareStreamingAdapter
      def each_normalized(events, &block)
        events.each(&block)
      end
    end

    FakeRunner = Data.define(:payloads) do
      def start
        payloads.each { |payload| yield payload, nil }
      end
    end

    FakeRunnerWithMetadata = Data.define(:pairs) do
      def start(&block)
        pairs.each(&block)
      end
    end

    private

    def streaming_adapter(&block)
      StreamingAdapter.new(block)
    end

    def sample_event(position)
      CDC::Core::ChangeEvent.new(operation: :insert, schema: "public", table: "orders", commit_lsn: position)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
