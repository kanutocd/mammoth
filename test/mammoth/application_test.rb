# frozen_string_literal: true

require "test_helper"

module Mammoth
  # rubocop:disable Metrics/ClassLength
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

    def test_default_postgres_source_receives_application_checkpoint_store
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))
        app = Application.new(Configuration.load(config_path), sink: DeliveryWorkerTest::RecordingSink.new)

        assert_instance_of Sources::Postgres, app.consumer.source
        assert_same app.checkpoint_store, app.consumer.source.checkpoint_store
      end
    end

    def test_builds_operational_state_adapter_from_config
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(
          File.join(dir, "mammoth.yml"),
          minimal_config(sqlite_path: db_path) + <<~YAML

            operational_state:
              adapter: sqlite
          YAML
        )

        app = Application.new(Configuration.load(config_path), source: [])

        assert_instance_of OperationalState::SQLiteAdapter, app.state_adapter
        assert_same app.state_adapter.checkpoint_store, app.checkpoint_store
      end
    end

    def test_sqlite_store_returns_nil_for_non_sqlite_state_adapter
      app = Application.allocate
      app.instance_variable_set(:@state_adapter, Object.new)

      assert_nil app.sqlite_store
    end

    def test_builds_fanout_delivery_worker_from_destinations_config
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(
          File.join(dir, "mammoth.yml"),
          minimal_config(sqlite_path: db_path).sub(/^webhook:.*?(?=^retry:)/m, <<~YAML)
            destinations:
              - name: primary_webhook
                type: webhook
                url: https://example.com/webhooks/postgres
                timeout_seconds: 5
              - name: audit_webhook
                type: webhook
                url: https://example.com/webhooks/audit
                timeout_seconds: 5

          YAML
        )
        app = Application.new(Configuration.load(config_path), source: [])

        assert_instance_of FanoutDeliveryWorker, app.delivery_worker
        assert_equal %w[primary_webhook audit_webhook], app.delivery_worker.delivery_workers.map(&:sink).map(&:name)
      end
    end

    def test_builds_destination_policy_from_destinations_config
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), destination_policy_config(db_path))
        app = Application.new(Configuration.load(config_path), source: [])
        worker = app.delivery_worker

        assert_instance_of DeliveryWorker, worker
        refute worker.enabled
        assert_equal 2, worker.max_attempts
        assert_equal [3], worker.retry_schedule
        assert_equal 7, worker.sink.timeout_seconds
        assert_equal ["orders"], worker.route_filter.tables
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

    def test_processes_event_delivery_inline_when_runtime_is_absent
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))
        sink = DeliveryWorkerTest::RecordingSink.new
        app = Application.new(
          Configuration.load(config_path),
          source: [sample_event("event-inline", "0/inline")],
          sink: sink,
          sleeper: ->(_seconds) {}
        )

        assert_equal 1, app.start
        checkpoint = CheckpointStore.new(app.sqlite_store).fetch(
          source_name: "local_mammoth",
          slot_name: "mammoth_prod"
        )

        assert_equal "0/inline", checkpoint.fetch("last_lsn")
      end
    end

    def test_concurrent_runtime_can_disable_preserve_order
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
              preserve_order: false
          YAML
        )
        sink = DeliveryWorkerTest::RecordingSink.new
        envelope = FakeEnvelope.new([sample_event("event-no-order", "0/no-order")], "tx-no-order")
        app = Application.new(Configuration.load(config_path), source: [envelope], sink: sink, sleeper: ->(_seconds) {})

        assert_equal 1, app.start
        refute CDC::Concurrent::ProcessorPool.last_options.fetch(:preserve_order)
      end
    end

    def test_concurrent_runtime_processes_configured_batches
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(
          File.join(dir, "mammoth.yml"),
          minimal_config(sqlite_path: db_path) + <<~YAML

            runtime:
              adapter: concurrent
              concurrency: 2
              batch_size: 2
          YAML
        )
        sink = DeliveryWorkerTest::RecordingSink.new
        source = [
          sample_event("event-1", "0/1"),
          sample_event("event-2", "0/2"),
          sample_event("event-3", "0/3")
        ]
        app = Application.new(Configuration.load(config_path), source: source, sink: sink, sleeper: ->(_seconds) {})

        assert_equal 3, app.start
        assert_equal 3, DeliveredEnvelopeStore.new(app.sqlite_store).count
      end
    end

    def test_shutdown_skips_runtime_without_shutdown_hook
      runtime = Object.new
      app = Application.allocate
      app.instance_variable_set(:@consumer, FakeConsumer.new([sample_event("event-no-shutdown", "0/no-shutdown")]))
      app.instance_variable_set(:@delivery_worker, DeliveryWorkerTest::RecordingSink.new)

      app.define_singleton_method(:build_runtime) { runtime }
      def app.runtime_batching?(_runtime) = false
      def app.process_work(_runtime, _work) = nil

      assert_equal 1, app.start
      refute_respond_to runtime, :shutdown
    end

    FakeEnvelope = Data.define(:events, :transaction_id)
    FakeConsumer = Data.define(:items) do
      def start(&block)
        items.each(&block)
      end
    end

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

    def destination_policy_config(db_path)
      minimal_config(sqlite_path: db_path).sub(/^webhook:.*?(?=^retry:)/m, <<~YAML)
        destinations:
          - name: primary_webhook
            type: webhook
            enabled: false
            url: https://example.com/webhooks/postgres
            timeout_seconds: 7
            route:
              schemas:
                - public
              tables:
                - orders
              operations:
                - insert
            retry:
              max_attempts: 2
              schedule_seconds:
                - 3

      YAML
    end
  end
  # rubocop:enable Metrics/ClassLength
end
