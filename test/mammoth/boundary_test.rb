# frozen_string_literal: true

require "test_helper"

module Mammoth
  class BoundaryTest < Minitest::Test
    LIB_ROOT = File.expand_path("../../lib", __dir__)
    POSTGRES_SOURCE_FILE = File.join(LIB_ROOT, "mammoth", "sources", "postgres.rb")

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
    end

    def test_postgres_source_delegates_streaming_normalization_to_source_adapter
      body = File.read(POSTGRES_SOURCE_FILE)

      assert_match(/each_normalized/, body)
      assert_match(/stream_event/, body)
      refute_match(/Data\.define|TransactionEnvelope\.new/, body)
      refute_match(/transaction_buffer|begin_message\?|commit_message\?/, body)
    end

    def test_application_does_not_construct_pgoutput_components_directly
      body = File.read(File.join(LIB_ROOT, "mammoth", "application.rb"))

      refute_match(/CdcSource\.new|Pgoutput::/, body)
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

    def ruby_files
      Dir.glob(File.join(LIB_ROOT, "**", "*.rb"))
    end

    def relative_path(path)
      path.delete_prefix("#{File.expand_path("../..", __dir__)}/")
    end
  end
end
