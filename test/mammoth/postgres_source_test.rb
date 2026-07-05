# frozen_string_literal: true

require "test_helper"

module Mammoth
  # rubocop:disable Metrics/ClassLength
  class PostgresSourceTest < Minitest::Test
    def test_streams_from_injected_cdc_source_components
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload-1"]),
        parser: ->(payload) { "parsed-#{payload}" },
        decoder: ->(message) { "decoded-#{message}" },
        adapter: ->(decoded) { sample_event(decoded) }
      )

      assert_equal [sample_event("decoded-parsed-payload-1")], source.each.to_a
    end

    def test_each_returns_enumerator_without_block
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new([]),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: ->(decoded) { sample_event(decoded) }
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
        adapter: ->(decoded) { sample_event(decoded) }
      )

      assert_equal "parsed-payload", source.each.first.fetch("source_position")
    end

    def test_decoder_can_use_decode_interface
      decoder = Object.new
      def decoder.decode(message) = "decoded-#{message}"
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: decoder,
        adapter: ->(decoded) { sample_event(decoded) }
      )

      assert_equal "decoded-payload", source.each.first.fetch("source_position")
    end

    def test_adapter_can_use_normalize_interface
      adapter = Object.new
      def adapter.normalize(decoded) = { "operation" => "insert", "source_position" => decoded }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: adapter
      )

      assert_equal "payload", source.each.first.fetch("source_position")
    end

    def test_ignores_nil_decoded_messages
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: ->(_message) { nil },
        adapter: ->(decoded) { sample_event(decoded) }
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
        adapter: ->(decoded) { sample_event(decoded) }
      )

      assert_equal "processed-payload", source.each.first.fetch("source_position")
    end

    def test_decoder_decode_interface_can_receive_metadata
      decoder = Object.new
      def decoder.decode(message, metadata) = "#{message}-#{metadata.fetch(:lsn)}"
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunnerWithMetadata.new([["payload", { lsn: "0/42" }]]),
        parser: ->(payload) { payload },
        decoder: decoder,
        adapter: ->(decoded) { sample_event(decoded) }
      )

      assert_equal "payload-0/42", source.each.first.fetch("source_position")
    end

    def test_decoder_call_interface_can_receive_metadata
      decoder = ->(message, metadata) { "#{message}-#{metadata.fetch(:lsn)}" }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunnerWithMetadata.new([["payload", { lsn: "0/43" }]]),
        parser: ->(payload) { payload },
        decoder: decoder,
        adapter: ->(decoded) { sample_event(decoded) }
      )

      assert_equal "payload-0/43", source.each.first.fetch("source_position")
    end

    def test_adapter_can_return_array_of_work
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: ->(decoded) { [nil, sample_event(decoded)] }
      )

      assert_equal [sample_event("payload")], source.each.to_a
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

    # rubocop:disable Metrics/AbcSize
    def test_buffers_pgoutput_transaction_until_commit
      decoded_messages = {
        "begin" => FakeBegin.new("tx-1"),
        "row-1" => "row-1",
        "row-2" => "row-2",
        "commit" => FakeCommit.new("0/99")
      }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(%w[begin row-1 row-2 commit]),
        parser: ->(payload) { payload },
        decoder: ->(message) { decoded_messages.fetch(message) },
        adapter: ->(decoded) { sample_event(decoded) }
      )

      emitted = source.each.to_a

      assert_equal 1, emitted.length
      envelope = emitted.fetch(0)
      assert_equal "tx-1", envelope.transaction_id
      assert_equal "0/99", envelope.commit_lsn
      assert_equal 2, envelope.events.length
      assert_equal(%w[row-1 row-2], envelope.events.map { |event| event.fetch("source_position") })
    end
    # rubocop:enable Metrics/AbcSize

    def test_commit_metadata_supplies_transaction_commit_lsn
      decoded_messages = {
        "begin" => FakeBegin.new("tx-2"),
        "row" => { "operation" => "insert" },
        "commit" => FakeCommit.new(nil)
      }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunnerWithMetadata.new([
                                             ["begin", { lsn: "0/1" }],
                                             ["row", { lsn: "0/2" }],
                                             ["commit", { lsn: "0/3" }]
                                           ]),
        parser: ->(payload) { payload },
        decoder: ->(message, _metadata) { decoded_messages.fetch(message) },
        adapter: ->(decoded) { decoded }
      )

      envelope = source.each.first

      assert_equal "tx-2", envelope.transaction_id
      assert_equal "0/3", envelope.commit_lsn
      assert_equal "0/2", envelope.events.first.fetch("source_position")
    end

    def test_decoder_can_emit_array_of_decoded_messages
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["payload"]),
        parser: ->(payload) { payload },
        decoder: ->(_message) { ["row-1", nil, "row-2"] },
        adapter: ->(decoded) { sample_event(decoded) }
      )

      assert_equal(%w[row-1 row-2], source.each.map { |event| event.fetch("source_position") })
    end

    def test_commit_message_without_active_transaction_buffer_is_ignored
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["commit"]),
        parser: ->(payload) { payload },
        decoder: ->(_message) { FakeCommit.new("0/commit") },
        adapter: ->(decoded) { sample_event(decoded) }
      )

      assert_equal [], source.each.to_a
    end

    def test_transaction_buffer_ignores_nil_normalized_work
      decoded_messages = {
        "begin" => FakeBegin.new("tx-empty"),
        "row" => "row",
        "commit" => FakeCommit.new("0/empty")
      }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(%w[begin row commit]),
        parser: ->(payload) { payload },
        decoder: ->(message) { decoded_messages.fetch(message) },
        adapter: ->(_decoded) { nil }
      )

      envelope = source.each.first

      assert_equal "tx-empty", envelope.transaction_id
      assert_equal [], envelope.events
      assert_equal "0/empty", envelope.commit_lsn
    end

    def test_commit_lsn_falls_back_to_first_event_position
      decoded_messages = {
        "begin" => FakeBegin.new("tx-event-position"),
        "row" => { "operation" => "insert", "source_position" => "0/event" },
        "commit" => FakeCommit.new(nil)
      }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(%w[begin row commit]),
        parser: ->(payload) { payload },
        decoder: ->(message) { decoded_messages.fetch(message) },
        adapter: ->(decoded) { decoded }
      )

      envelope = source.each.first

      assert_equal "0/event", envelope.commit_lsn
    end

    def test_metadata_hash_must_be_hash_like
      decoded_messages = {
        "begin" => FakeBeginWithMetadata.new("tx-metadata", "not-a-hash"),
        "row" => { "operation" => "insert", "source_position" => "0/row" },
        "commit" => FakeCommit.new("0/commit")
      }
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(%w[begin row commit]),
        parser: ->(payload) { payload },
        decoder: ->(message) { decoded_messages.fetch(message) },
        adapter: ->(decoded) { decoded }
      )

      assert_equal({}, source.each.first.metadata)
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
        adapter: ->(decoded) { sample_event(decoded) }
      )

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/pgoutput parser must respond/, error.message)
    end

    def test_reports_missing_default_pgoutput_client
      source = Sources::Postgres.new(Configuration.load(fixture_config_path))

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
        adapter: ->(decoded) { sample_event(decoded) }
      )

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/PostgreSQL CDC source failed: stream exploded/, error.message)
    end

    FakeBegin = Data.define(:transaction_id)
    FakeBeginWithMetadata = Data.define(:transaction_id, :metadata)
    FakeCommit = Data.define(:commit_lsn)

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

    def sample_event(position)
      { "operation" => "insert", "source_position" => position }
    end
  end
  # rubocop:enable Metrics/ClassLength
end
