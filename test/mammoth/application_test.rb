# frozen_string_literal: true

require "test_helper"

module Mammoth
  class ApplicationTest < Minitest::Test
    def test_processes_injected_source_through_delivery_worker
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))
        sink = DeliveryWorkerTest::RecordingSink.new
        source = [sample_event("event-1", "0/1"), sample_event("event-2", "0/2")]
        app = Application.new(Configuration.load(config_path), source: source, sink: sink, sleeper: ->(_seconds) {})

        assert_equal 2, app.start
        checkpoint = CheckpointStore.new(app.sqlite_store).fetch(
          source_name: "local_mammoth",
          slot_name: "mammoth_prod"
        )

        assert_equal "0/2", checkpoint.fetch("last_lsn")
      end
    end

    def test_dead_letters_failed_injected_source_event
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))
        app = Application.new(
          Configuration.load(config_path),
          source: [sample_event("event-1", "0/1")],
          sink: DeliveryWorkerTest::FailingSink.new,
          sleeper: ->(_seconds) {}
        )

        assert_equal 1, app.start
        assert_equal 1, DeadLetterStore.new(app.sqlite_store).count(status: "pending")
      end
    end

    # rubocop:disable Metrics/MethodLength
    def test_processes_transaction_envelopes_through_concurrent_runtime
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(
          File.join(dir, "mammoth.yml"),
          minimal_config(sqlite_path: db_path) + <<~YAML

            delivery:
              unit: transaction
              ordering:
                scope: transaction

            runtime:
              adapter: concurrent
              concurrency: 3
              preserve_order: true
              timeout_seconds:
          YAML
        )
        sink = DeliveryWorkerTest::RecordingSink.new
        envelope = FakeEnvelope.new([sample_event("event-1", "0/1"), sample_event("event-2", "0/2")], "tx-1")
        app = Application.new(Configuration.load(config_path), source: [envelope], sink: sink, sleeper: ->(_seconds) {})

        assert_equal 1, app.start
        checkpoint = CheckpointStore.new(app.sqlite_store).fetch(
          source_name: "local_mammoth",
          slot_name: "mammoth_prod"
        )

        assert_equal "0/2", checkpoint.fetch("last_lsn")
        assert_equal 3, CDC::Concurrent::ProcessorPool.last_options.fetch(:concurrency)
        assert CDC::Concurrent::ProcessorPool.last_options.fetch(:preserve_order)
      end
    end
    # rubocop:enable Metrics/MethodLength

    def test_processes_transaction_envelopes_inline_without_runtime
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(
          File.join(dir, "mammoth.yml"),
          minimal_config(sqlite_path: db_path) + <<~YAML

            delivery:
              unit: transaction
          YAML
        )
        sink = DeliveryWorkerTest::RecordingSink.new
        envelope = FakeEnvelope.new([sample_event("event-1", "0/1")], "tx-inline")
        app = Application.new(Configuration.load(config_path), source: [envelope], sink: sink, sleeper: ->(_seconds) {})

        assert_equal 1, app.start
        checkpoint = CheckpointStore.new(app.sqlite_store).fetch(
          source_name: "local_mammoth",
          slot_name: "mammoth_prod"
        )

        assert_equal "0/1", checkpoint.fetch("last_lsn")
      end
    end

    def test_concurrent_runtime_defaults_to_preserve_order
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(
          File.join(dir, "mammoth.yml"),
          minimal_config(sqlite_path: db_path) + <<~YAML

            delivery:
              unit: transaction

            runtime:
              adapter: concurrent
              concurrency: 2
          YAML
        )
        sink = DeliveryWorkerTest::RecordingSink.new
        envelope = FakeEnvelope.new([sample_event("event-1", "0/1")], "tx-default-order")
        app = Application.new(Configuration.load(config_path), source: [envelope], sink: sink, sleeper: ->(_seconds) {})

        assert_equal 1, app.start
        assert CDC::Concurrent::ProcessorPool.last_options.fetch(:preserve_order)
      end
    end

    FakeEnvelope = Data.define(:events, :transaction_id)

    private

    def sample_event(event_id, position)
      {
        "event_id" => event_id,
        "source" => "postgresql",
        "operation" => "insert",
        "namespace" => "public",
        "entity" => "orders",
        "source_position" => position,
        "data" => { "id" => event_id }
      }
    end
  end
end
