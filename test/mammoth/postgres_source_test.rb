# frozen_string_literal: true

require "test_helper"
require "cdc/core"
require "pgoutput/decoder/events"
require "pgoutput/source_adapter"

module Mammoth
  # rubocop:disable Metrics/ClassLength
  class PostgresSourceTest < Minitest::Test
    HealthyPublicationInspector = Object.new
    def HealthyPublicationInspector.inspect(_publication_names) = []

    def run
      Sources::PostgresPublicationInspector.stub(:new, HealthyPublicationInspector) { super }
    end

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

    def test_acknowledge_delegates_durable_progress_to_runner
      runner = RecordingAckRunner.new
      source = Sources::Postgres.new(Configuration.load(fixture_config_path), runner: runner)

      assert_equal 42, source.acknowledge("0/2A")
      assert_equal ["0/2A"], runner.acknowledgements
    end

    def test_acknowledge_wraps_runner_failures
      runner = Object.new
      def runner.ack(_lsn) = raise("feedback failed")
      source = Sources::Postgres.new(Configuration.load(fixture_config_path), runner:)

      error = assert_raises(ReplicationError) { source.acknowledge("0/2A") }

      assert_match(/WAL acknowledgement failed: feedback failed/, error.message)
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

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
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
                                             ["begin", { lsn: "0/A" }],
                                             ["row", { lsn: "0/B" }],
                                             ["commit", { lsn: "0/C" }]
                                           ]),
        parser: ->(payload) { payload },
        decoder: ->(message, _metadata) { decoded_messages.fetch(message) },
        adapter: Pgoutput::SourceAdapter::Cdc.new
      )

      progress_positions = []
      envelope = nil
      source.each do |work|
        envelope = work
        progress_positions << [
          source.progress_position_for(work),
          source.progress_position_for(work.events.first)
        ]
      end

      assert_instance_of CDC::Core::TransactionEnvelope, envelope
      assert_equal "11", envelope.commit_lsn
      assert_instance_of CDC::Core::ChangeEvent, envelope.events.first
      assert_equal "0/B", envelope.events.first.commit_lsn
      assert_equal [["0/C", "0/C"]], progress_positions
      assert_nil source.progress_position_for(envelope)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

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

    def test_rejects_non_lsn_transport_position_for_acknowledgement
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunnerWithMetadata.new([["row", { lsn: "11" }]]),
        parser: ->(payload) { payload },
        decoder: ->(message, _metadata) { message },
        adapter: BareStreamingAdapter.new
      )

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/invalid PostgreSQL transport LSN/, error.message)
    end

    def test_preserves_integer_transport_position_for_acknowledgement
      positions = []
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunnerWithMetadata.new([["row", { wal_end: 42 }]]),
        parser: ->(payload) { payload },
        decoder: ->(message, _metadata) { message },
        adapter: BareStreamingAdapter.new
      )

      source.each { |work| positions << source.progress_position_for(work) }

      assert_equal [42], positions
    end

    # rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/MethodLength
    def test_checkpoints_and_acknowledges_transport_lsn_instead_of_decimal_commit_lsn
      with_temp_dir do |dir|
        events = Pgoutput::Decoder::Events
        runner = RecordingMetadataRunner.new([
                                               ["begin", { lsn: "0/A" }],
                                               ["row", { lsn: "0/B" }],
                                               ["commit", { lsn: "0/C" }]
                                             ])
        decoded = {
          "begin" => events::Begin.new(42, 10, 123_456),
          "row" => events::Insert.new(42, 7, "public", "orders", { "id" => 1 }),
          "commit" => events::Commit.new(42, 0, 11, 12, 123_789)
        }
        source = Sources::Postgres.new(
          Configuration.load(fixture_config_path),
          runner: runner,
          parser: ->(payload) { payload },
          decoder: ->(message, _metadata) { decoded.fetch(message) },
          adapter: Pgoutput::SourceAdapter::Cdc.new
        )
        checkpoint_store = CheckpointStore.new(SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!)
        coordinator = DeliveryProgressCoordinator.new(
          checkpoint_store: checkpoint_store,
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          acknowledger: source.method(:acknowledge),
          position_resolver: source.method(:progress_position_for)
        )

        source.each do |work|
          assert_equal "11", work.commit_lsn
          coordinator.register(work, group_end: true)
          coordinator.complete(work)
        end

        checkpoint = checkpoint_store.fetch(source_name: "local_mammoth", slot_name: "mammoth_prod")
        assert_equal "0/C", checkpoint.fetch("last_lsn")
        assert_equal ["0/C"], runner.acknowledgements
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/MethodLength

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

    def test_adapter_without_stream_event_can_normalize_decoded_values
      adapter = BareStreamingAdapter.new
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["row"]),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: adapter
      )

      event = source.each.first

      assert_instance_of CDC::Core::ChangeEvent, event
      assert_equal "row", event.commit_lsn
    end

    def test_rejects_non_core_adapter_output
      source = Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: FakeRunner.new(["row"]),
        parser: ->(payload) { payload },
        decoder: ->(message) { message },
        adapter: NonCoreStreamingAdapter.new
      )

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/source adapter yielded non-core work: String/, error.message)
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

    def test_preflight_rejects_missing_slot_when_auto_creation_is_disabled
      runner = PreflightRunner.new(nil)
      source = preflight_source(runner)

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/slot mammoth_prod is missing/, error.message)
      refute runner.started
    end

    def test_preflight_allows_missing_slot_for_fresh_auto_created_stream
      config = Configuration.load(fixture_config_path)
      config.data.fetch("replication")["auto_create_slot"] = true
      runner = PreflightRunner.new(nil)

      preflight_source(runner, config: config).each.to_a

      assert runner.started
    end

    def test_preflight_refuses_to_recreate_missing_slot_for_persisted_checkpoint
      with_temp_dir do |dir|
        config = Configuration.load(fixture_config_path)
        config.data.fetch("replication")["auto_create_slot"] = true
        checkpoint_store = CheckpointStore.new(SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!)
        checkpoint_store.write(
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          last_lsn: "0/10"
        )
        runner = PreflightRunner.new(nil)
        source = preflight_source(runner, config: config, checkpoint_store: checkpoint_store)

        error = assert_raises(ReplicationError) { source.each.to_a }

        assert_match(%r{refusing to recreate.*checkpoint 0/10}, error.message)
        refute source.send(:runner_options).fetch(:auto_create_slot)
        refute runner.started
      end
    end

    def test_preflight_rejects_temporary_slot_checkpoint_resume
      config = config_with_start_lsn("0/10")
      config.data.fetch("replication")["temporary_slot"] = true
      runner = PreflightRunner.new(healthy_slot_status)

      error = assert_raises(ReplicationError) { preflight_source(runner, config: config).each.to_a }

      assert_match(/cannot resume.*temporary slot/, error.message)
      assert_equal 0, runner.inspections
    end

    def test_preflight_requires_pgoutput_client_slot_inspection
      runner = Object.new
      def runner.start = nil

      error = assert_raises(ReplicationError) { preflight_source(runner).each.to_a }

      assert_match(/pgoutput-client 0\.4\+/, error.message)
    end

    def test_preflight_wraps_slot_inspection_failure
      runner = PreflightRunner.new(RuntimeError.new("catalog unavailable"))

      error = assert_raises(ReplicationError) { preflight_source(runner).each.to_a }

      assert_match(/slot preflight failed: catalog unavailable/, error.message)
    end

    def test_preflight_accepts_primary_key_index_full_and_insert_only_tables # rubocop:disable Metrics/MethodLength
      tables = [
        publication_table(table_name: "primary_orders", replica_identity: "d", primary_key_usable: true),
        publication_table(
          table_name: "indexed_orders",
          replica_identity: "i",
          replica_identity_index_usable: true
        ),
        publication_table(table_name: "full_orders", replica_identity: "f"),
        publication_table(
          table_name: "insert_only",
          publishes_updates: false,
          publishes_deletes: false,
          replica_identity: "n"
        )
      ]
      inspector = Struct.new(:tables) do
        def inspect(_publication_names) = tables
      end.new(tables)
      runner = PreflightRunner.new(healthy_slot_status)

      preflight_source(runner, publication_inspector: inspector).each.to_a

      assert runner.started
    end

    def test_preflight_rejects_update_delete_tables_without_usable_identity
      tables = [
        publication_table(table_name: "orders", replica_identity: "d"),
        publication_table(table_name: "audit_log", replica_identity: "n", publishes_updates: false)
      ]
      inspector = Struct.new(:tables) do
        def inspect(_publication_names) = tables
      end.new(tables)

      error = assert_raises(ReplicationError) do
        preflight_source(
          PreflightRunner.new(healthy_slot_status),
          publication_inspector: inspector
        ).each.to_a
      end

      assert_match(/replica identity preflight failed/, error.message)
      assert_match(%r{public\.orders.*actions=UPDATE/DELETE.*replica_identity=default}, error.message)
      assert_match(/public\.audit_log.*actions=DELETE.*replica_identity=nothing/, error.message)
      assert_match(/REPLICA IDENTITY USING INDEX/, error.message)
      assert_match(/REPLICA IDENTITY FULL/, error.message)
    end

    def test_preflight_wraps_unexpected_publication_inspection_failure
      inspector = Object.new
      def inspector.inspect(_publication_names) = raise("catalog unavailable")

      error = assert_raises(ReplicationError) do
        preflight_source(
          PreflightRunner.new(healthy_slot_status),
          publication_inspector: inspector
        ).each.to_a
      end

      assert_match(/replica identity preflight failed: catalog unavailable/, error.message)
    end

    def test_slot_health_normalizes_pgoutput_catalog_metrics
      runner = PreflightRunner.new(
        healthy_slot_status(
          active: true,
          retained_wal_bytes: 8192,
          safe_wal_size: 4096,
          inactive_since: nil,
          restart_lsn: "1/10",
          confirmed_flush_lsn: "1/20"
        )
      )

      health = preflight_source(runner).slot_health

      assert_predicate health, :ready?
      assert_equal "mammoth_prod", health.slot_name
      assert_equal 8192, health.retained_wal_bytes
      assert_equal 4096, health.safe_wal_size
      assert_equal 0x1_00000010, health.restart_lsn_bytes
      assert_equal 0x1_00000020, health.confirmed_flush_lsn_bytes
    end

    def test_slot_health_reports_missing_slot
      health = preflight_source(PreflightRunner.new(nil)).slot_health

      refute_predicate health, :present
      refute_predicate health, :ready?
      assert_equal "slot is missing", health.reason
    end

    def test_slot_health_wraps_inspection_failures
      source = preflight_source(PreflightRunner.new(RuntimeError.new("catalog unavailable")))

      error = assert_raises(ReplicationError) { source.slot_health }

      assert_match(/slot health inspection failed: catalog unavailable/, error.message)
    end

    def test_slot_health_preserves_mammoth_lsn_validation_errors
      source = preflight_source(PreflightRunner.new(healthy_slot_status(restart_lsn: "invalid")))

      error = assert_raises(ReplicationError) { source.slot_health }

      assert_match(/invalid PostgreSQL slot metric LSN/, error.message)
      refute_match(/slot health inspection failed/, error.message)
    end

    def test_slot_health_accepts_absent_optional_lsn
      health = preflight_source(
        PreflightRunner.new(healthy_slot_status(active: true, confirmed_flush_lsn: nil))
      ).slot_health

      assert_nil health.confirmed_flush_lsn_bytes
    end

    def test_preflight_rejects_wrong_slot_identity
      invalid_statuses = [
        healthy_slot_status(slot_name: "other"),
        healthy_slot_status(slot_type: "physical"),
        healthy_slot_status(plugin: "test_decoding"),
        healthy_slot_status(database: "other")
      ]

      errors = invalid_statuses.map do |status|
        assert_raises(ReplicationError) { preflight_source(PreflightRunner.new(status)).each.to_a }
      end

      assert_match(/wrong slot/, errors.fetch(0).message)
      assert_match(/logical pgoutput/, errors.fetch(1).message)
      assert_match(/logical pgoutput/, errors.fetch(2).message)
      assert_match(/different database/, errors.fetch(3).message)
    end

    def test_preflight_rejects_active_lost_and_unreserved_slots
      statuses = [
        healthy_slot_status(active: true),
        healthy_slot_status(wal_status: "lost"),
        healthy_slot_status(wal_status: "unreserved")
      ]

      errors = statuses.map do |status|
        assert_raises(ReplicationError) { preflight_source(PreflightRunner.new(status)).each.to_a }
      end

      assert_match(/already active/, errors.fetch(0).message)
      assert_match(/wal_status=lost/, errors.fetch(1).message)
      assert_match(/wal_status=unreserved/, errors.fetch(2).message)
    end

    def test_preflight_rejects_conflicted_invalidated_and_restartless_slots
      statuses = [
        healthy_slot_status(conflicting: true),
        healthy_slot_status(invalidation_reason: "wal_removed"),
        healthy_slot_status(restart_lsn: nil)
      ]

      errors = statuses.map do |status|
        assert_raises(ReplicationError) { preflight_source(PreflightRunner.new(status)).each.to_a }
      end

      assert_match(/is invalidated/, errors.fetch(0).message)
      assert_match(/invalidated: wal_removed/, errors.fetch(1).message)
      assert_match(/no reachable restart LSN/, errors.fetch(2).message)
    end

    def test_preflight_rejects_checkpoint_older_than_slot_wal_boundaries
      config = config_with_start_lsn("0/10")
      statuses = [
        healthy_slot_status(restart_lsn: "0/11"),
        healthy_slot_status(confirmed_flush_lsn: "0/12")
      ]

      errors = statuses.map do |status|
        assert_raises(ReplicationError) do
          preflight_source(PreflightRunner.new(status), config: config).each.to_a
        end
      end

      assert_match(%r{restart_lsn=0/11.*advanced past}, errors.fetch(0).message)
      assert_match(%r{confirmed_flush_lsn=0/12.*advanced past}, errors.fetch(1).message)
    end

    def test_preflight_accepts_reachable_checkpoint_and_optional_flush_boundary
      config = config_with_start_lsn("0/10")
      runner = PreflightRunner.new(
        healthy_slot_status(restart_lsn: "0/F", confirmed_flush_lsn: nil)
      )

      preflight_source(runner, config: config).each.to_a

      assert runner.started
    end

    def test_preflight_rejects_invalid_checkpoint_and_catalog_lsns
      invalid_checkpoint = assert_raises(ReplicationError) do
        preflight_source(
          PreflightRunner.new(healthy_slot_status),
          config: config_with_start_lsn("not-an-lsn")
        ).each.to_a
      end
      invalid_catalog = assert_raises(ReplicationError) do
        preflight_source(
          PreflightRunner.new(healthy_slot_status(restart_lsn: "not-an-lsn")),
          config: config_with_start_lsn("0/10")
        ).each.to_a
      end

      assert_match(/invalid PostgreSQL resume checkpoint LSN/, invalid_checkpoint.message)
      assert_match(/invalid PostgreSQL restart_lsn LSN/, invalid_catalog.message)
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
      broken_runner.extend(HealthySlotRunner)
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

    module HealthySlotRunner
      def slot_status
        {
          slot_name: "mammoth_prod",
          plugin: "pgoutput",
          slot_type: "logical",
          database: "app_development",
          active: false,
          restart_lsn: "0/0",
          confirmed_flush_lsn: "0/0"
        }
      end
    end

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
      def each_normalized(events)
        events.each do |event|
          yield CDC::Core::ChangeEvent.new(
            operation: :insert,
            schema: "public",
            table: "orders",
            commit_lsn: event
          )
        end
      end
    end

    class NonCoreStreamingAdapter
      def each_normalized(events, &block)
        events.each(&block)
      end
    end

    FakeRunner = Data.define(:payloads) do
      include HealthySlotRunner

      def start
        payloads.each { |payload| yield payload, nil }
      end
    end

    FakeRunnerWithMetadata = Data.define(:pairs) do
      include HealthySlotRunner

      def start(&block)
        pairs.each(&block)
      end
    end

    class RecordingMetadataRunner
      include HealthySlotRunner

      attr_reader :pairs, :acknowledgements

      def initialize(pairs)
        @pairs = pairs
        @acknowledgements = []
      end

      def start(&block)
        pairs.each(&block)
      end

      def ack(lsn)
        acknowledgements << lsn
      end
    end

    class RecordingAckRunner
      attr_reader :acknowledgements

      def initialize
        @acknowledgements = []
      end

      def ack(lsn)
        acknowledgements << lsn
        42
      end
    end

    class PreflightRunner
      attr_reader :status, :inspections, :started

      def initialize(status)
        @status = status
        @inspections = 0
        @started = false
      end

      def slot_status
        @inspections += 1
        raise status if status.is_a?(Exception)

        status
      end

      def start
        @started = true
      end
    end

    private

    def preflight_source(runner, config: Configuration.load(fixture_config_path), checkpoint_store: nil,
                         publication_inspector: HealthyPublicationInspector)
      Sources::Postgres.new(
        config,
        runner: runner,
        adapter: BareStreamingAdapter.new,
        checkpoint_store: checkpoint_store,
        publication_inspector: publication_inspector
      )
    end

    def config_with_start_lsn(lsn)
      Configuration.load(fixture_config_path).tap do |config|
        config.data.fetch("replication")["start_lsn"] = lsn
      end
    end

    def healthy_slot_status(**overrides)
      {
        slot_name: "mammoth_prod",
        plugin: "pgoutput",
        slot_type: "logical",
        database: "app_development",
        active: false,
        restart_lsn: "0/0",
        confirmed_flush_lsn: "0/0",
        wal_status: "reserved",
        conflicting: false,
        invalidation_reason: nil,
        **overrides
      }
    end

    def publication_table(**overrides)
      Sources::PostgresPublicationTable.new(
        schema_name: "public",
        table_name: "orders",
        publishes_updates: true,
        publishes_deletes: true,
        replica_identity: "d",
        primary_key_usable: false,
        replica_identity_index_usable: false,
        **overrides
      )
    end

    def streaming_adapter(&block)
      StreamingAdapter.new(block)
    end

    def sample_event(position)
      CDC::Core::ChangeEvent.new(operation: :insert, schema: "public", table: "orders", commit_lsn: position)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
