# frozen_string_literal: true

require "test_helper"
require "pgoutput/decoder/events"
require "pgoutput/source_adapter"

module Mammoth
  BOUNDARY_SLOT_STATUS = {
    slot_name: "mammoth_prod", plugin: "pgoutput", slot_type: "logical",
    database: "app_development", active: false, restart_lsn: "0/0"
  }.freeze

  class BoundaryTest < Minitest::Test
    PROJECT_ROOT = File.expand_path("../..", __dir__)
    LIB_ROOT = File.expand_path("../../lib", __dir__)
    SIG_ROOT = File.expand_path("../../sig", __dir__)
    POSTGRES_SOURCE_FILE = File.join(LIB_ROOT, "mammoth", "sources", "postgres.rb")
    POSTGRES_SOURCE_SIGNATURE = File.join(SIG_ROOT, "mammoth", "sources", "postgres.rbs")
    OPERATIONAL_STATE_CONSUMERS = %w[
      application.rb
      cli.rb
      dead_letter_commands.rb
      delivery_progress_coordinator.rb
      observability_snapshot.rb
      status.rb
      commands/bootstrap_command.rb
      commands/dead_letters_command.rb
      commands/status_command.rb
    ].map { |path| File.join(LIB_ROOT, "mammoth", path) }.freeze

    def test_only_postgres_source_mentions_pgoutput_components
      offenders = ruby_files.filter_map do |path|
        next if path == POSTGRES_SOURCE_FILE

        body = File.read(path)
        next unless body.match?(%r{Pgoutput::|pgoutput[_/-]})

        relative_path(path)
      end

      assert_empty(
        offenders,
        "pgoutput composition must stay behind Mammoth::Sources::Postgres: #{offenders.join(", ")}"
      )
    end

    def test_postgres_source_realizes_all_pgoutput_layers
      body = File.read(POSTGRES_SOURCE_FILE)

      assert_match(%r{pgoutput/client}, body)
      assert_match(/pgoutput-parser/, body)
      assert_match(%r{pgoutput/decoder}, body)
      assert_match(%r{pgoutput/source_adapter}, body)
      assert_match(/Pgoutput::Client::Runner/, body)
      assert_match(/Pgoutput::RelationTracker/, body)
      assert_match(/Pgoutput::Decoder/, body)
      assert_match(/Pgoutput::SourceAdapter::Cdc/, body)
      assert_match(/\.slot_status/, body)
      refute_match(/pg_replication_slots|PG\.connect|exec_params/, body)
    end

    def test_postgres_source_delegates_streaming_normalization_to_source_adapter
      body = File.read(POSTGRES_SOURCE_FILE)

      assert_match(/each_normalized/, body)
      assert_match(/stream_event/, body)
      refute_match(/Data\.define|TransactionEnvelope\.new/, body)
      refute_match(/transaction_buffer|begin_message\?|commit_message\?/, body)
    end

    def test_postgres_source_yields_exact_core_output_types_from_pgoutput_adapter
      events = Pgoutput::Decoder::Events
      source = postgres_source([
                                 events::Insert.new(42, 7, "public", "orders", { "id" => 1 }),
                                 events::Begin.new(43, 10, 123_456),
                                 events::Insert.new(43, 7, "public", "orders", { "id" => 2 }),
                                 events::Commit.new(43, 0, 11, 12, 123_789)
                               ])

      work = source.each.to_a

      assert_instance_of CDC::Core::ChangeEvent, work.fetch(0)
      assert_instance_of CDC::Core::TransactionEnvelope, work.fetch(1)
      assert_equal 1, work.fetch(1).events.size
      assert_instance_of CDC::Core::ChangeEvent, work.fetch(1).events.fetch(0)
    end

    def test_postgres_source_signature_exposes_only_core_output_types
      signature = File.read(POSTGRES_SOURCE_SIGNATURE)

      assert_match(/CDC::Core::ChangeEvent \| CDC::Core::TransactionEnvelope/, signature)
      refute_match(/Pgoutput/, signature)
    end

    def test_postgres_source_rejects_non_core_adapter_output
      source = postgres_source([Pgoutput::Decoder::Events::Insert.new(42, 7, "public", "orders", { "id" => 1 })])
      source.instance_variable_set(:@adapter, NonCoreBoundaryAdapter.new)

      error = assert_raises(ReplicationError) { source.each.to_a }

      assert_match(/yielded non-core work: String/, error.message)
    end

    def test_pgoutput_types_do_not_leak_into_downstream_signatures
      offenders = signature_files.filter_map do |path|
        next if path == POSTGRES_SOURCE_SIGNATURE
        next unless File.read(path).match?(/Pgoutput|pgoutput/)

        relative_path(path)
      end

      assert_empty offenders, "downstream signatures must depend on cdc-core types: #{offenders.join(", ")}"
    end

    def test_operational_state_consumers_do_not_construct_sqlite_dependencies
      offenders = OPERATIONAL_STATE_CONSUMERS.filter_map do |path|
        body = File.read(path)
        next unless body.match?(/SQLite3::|SQLiteStore\.connect|(?:Checkpoint|DeadLetter|DeliveredEnvelope)Store\.new/)

        relative_path(path)
      end

      assert_empty offenders, "operational consumers must use OperationalState::Adapter: #{offenders.join(", ")}"
    end

    def test_delivery_and_observability_realize_core_contracts
      assert_operator DeliveryProcessor, :<, CDC::Core::Processor
      assert_operator MetricsObserver, :<, CDC::Core::Observer
    end

    def test_application_does_not_construct_pgoutput_components_directly
      body = File.read(File.join(LIB_ROOT, "mammoth", "application.rb"))

      refute_match(/CdcSource\.new|Pgoutput::/, body)
    end

    def test_application_delegates_batching_to_runtime_layer
      body = File.read(File.join(LIB_ROOT, "mammoth", "application.rb"))

      assert_match(/runtime\.process\(work\)/, body)
      assert_match(/runtime\.flush/, body)
      refute_match(/flush_batch|process_batch|batch\s*<<|each_slice/, body)
    end

    def test_replication_consumer_does_not_reference_transport_configuration
      body = File.read(File.join(LIB_ROOT, "mammoth", "replication_consumer.rb"))

      refute_match(/slot|publication|postgres|pgoutput/i, body)
    end

    def test_delivery_runtime_does_not_manage_replication_slots_directly
      offenders = (ruby_files - [POSTGRES_SOURCE_FILE]).filter_map do |path|
        body = File.read(path)
        next unless body.match?(/pg_create_logical_replication_slot|CREATE_REPLICATION_SLOT|DROP_REPLICATION_SLOT/i)

        relative_path(path)
      end

      assert_empty(
        offenders,
        "replication slot lifecycle belongs to pgoutput-client: #{offenders.join(", ")}"
      )
    end

    private

    BoundaryRunner = Data.define(:messages, :slot_status) do
      def start
        messages.each.with_index do |message, index|
          yield message, { lsn: "0/#{index + 1}" }
        end
      end
    end

    class NonCoreBoundaryAdapter
      def each_normalized(events)
        events.each { |_event| yield "not-core" }
      end
    end

    def ruby_files
      Dir.glob(File.join(LIB_ROOT, "**", "*.rb"))
    end

    def signature_files
      Dir.glob(File.join(SIG_ROOT, "**", "*.rbs"))
    end

    def postgres_source(messages)
      Sources::Postgres.new(
        Configuration.load(fixture_config_path),
        runner: BoundaryRunner.new(messages, BOUNDARY_SLOT_STATUS),
        parser: ->(payload) { payload },
        decoder: ->(message, _metadata) { message },
        adapter: Pgoutput::SourceAdapter::Cdc.new
      )
    end

    def relative_path(path)
      path.delete_prefix("#{PROJECT_ROOT}/")
    end
  end

  class DeliveryProgressBoundaryTest < Minitest::Test
    LIB_ROOT = BoundaryTest::LIB_ROOT
    SIG_ROOT = BoundaryTest::SIG_ROOT
    POSTGRES_SOURCE_FILE = BoundaryTest::POSTGRES_SOURCE_FILE

    def test_pgoutput_acknowledgement_stays_in_postgres_source
      offenders = Dir.glob(File.join(LIB_ROOT, "**", "*.rb")).filter_map do |path|
        next if path == POSTGRES_SOURCE_FILE
        next unless File.read(path).match?(/(?:effective_)?runner\.ack\(/)

        path
      end

      assert_empty offenders, "pgoutput acknowledgement must stay behind Sources::Postgres: #{offenders.join(", ")}"
      source = File.read(POSTGRES_SOURCE_FILE)
      assert_match(/effective_runner\.ack\(lsn\)/, source)
      assert_match(/value_from\(metadata, :wal_end_lsn, :wal_end, :lsn\)/, source)
      assert_match(/def progress_position_for\(work\)/, source)
    end

    def test_delivery_progress_uses_injected_ports_without_transport_dependencies
      body = File.read(File.join(LIB_ROOT, "mammoth", "delivery_progress_coordinator.rb"))

      assert_match(/checkpoint_store\.write/, body)
      assert_match(/@acknowledger&\.call/, body)
      assert_match(/@position_resolver\.call\(work\)/, body)
      refute_match(%r{Pgoutput::|pgoutput[_/-]|effective_runner|Sources::Postgres}, body)
      refute_match(/SQLite3::|SQLiteStore\.connect|CheckpointStore\.new/, body)
      refute_match(/CDC::Core::(?:ChangeEvent|TransactionEnvelope)\.new/, body)
    end

    def test_progress_coordinator_signature_does_not_leak_pgoutput_types
      signature = File.read(File.join(SIG_ROOT, "mammoth", "delivery_progress_coordinator.rbs"))

      refute_match(/Pgoutput|pgoutput/, signature)
    end
  end
end
