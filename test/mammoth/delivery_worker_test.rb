# frozen_string_literal: true

require "test_helper"

module Mammoth
  class DeliveryWorkerTest < Minitest::Test
    def test_delivers_and_checkpoints_successful_event
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        worker = build_worker(sqlite, sink: RecordingSink.new)

        result = worker.deliver(sample_event)
        checkpoint = CheckpointStore.new(sqlite).fetch(source_name: "local_mammoth", slot_name: "mammoth_prod")

        assert_equal "delivered", result.fetch(:status)
        assert_equal 1, result.fetch(:attempts)
        assert_equal "0/16F4A8B0", checkpoint.fetch("last_lsn")
        assert_equal 0, DeadLetterStore.new(sqlite).count
      end
    end

    def test_retries_before_success
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = FlakySink.new(failures_before_success: 1)
        sleeps = []
        worker = build_worker(sqlite, sink: sink, sleeper: ->(seconds) { sleeps << seconds })

        result = worker.deliver(sample_event)

        assert_equal "delivered", result.fetch(:status)
        assert_equal 2, result.fetch(:attempts)
        assert_equal [1], sleeps
        assert_equal 0, DeadLetterStore.new(sqlite).count
      end
    end

    def test_dead_letters_after_retry_exhaustion
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        worker = build_worker(sqlite, sink: FailingSink.new, sleeper: ->(_seconds) {})

        result = worker.deliver(sample_event)
        dlq = DeadLetterStore.new(sqlite)

        assert_equal "dead_lettered", result.fetch(:status)
        assert_equal 3, result.fetch(:attempts)
        assert_equal 1, dlq.count(status: "pending")
        assert_equal 0, CheckpointStore.new(sqlite).count
      end
    end

    def test_reuses_last_retry_delay_when_attempts_exceed_schedule
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sleeps = []
        worker = DeliveryWorker.new(
          sink: FailingSink.new,
          checkpoint_store: CheckpointStore.new(sqlite),
          dead_letter_store: DeadLetterStore.new(sqlite),
          delivered_envelope_store: DeliveredEnvelopeStore.new(sqlite),
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          max_attempts: 4,
          retry_schedule: [2],
          sleeper: ->(seconds) { sleeps << seconds }
        )

        result = worker.deliver(sample_event)

        assert_equal "dead_lettered", result.fetch(:status)
        assert_equal [2, 2, 2], sleeps
      end
    end

    def test_disabled_destination_skips_and_checkpoints_without_delivery
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = RecordingSink.new
        worker = build_worker(sqlite, sink: sink, enabled: false)

        result = worker.deliver(sample_event)
        checkpoint = CheckpointStore.new(sqlite).fetch(source_name: "local_mammoth", slot_name: "mammoth_prod")

        assert_equal "skipped", result.fetch(:status)
        assert_equal "disabled", result.fetch(:reason)
        assert_equal 0, result.fetch(:attempts)
        assert_equal 0, sink.delivered_events
        assert_equal "0/16F4A8B0", checkpoint.fetch("last_lsn")
        assert_equal 0, DeliveredEnvelopeStore.new(sqlite).count
      end
    end

    def test_route_mismatch_skips_and_checkpoints_without_delivery
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = RecordingSink.new
        route_filter = RouteFilter.new("tables" => ["users"])
        worker = build_worker(sqlite, sink: sink, route_filter: route_filter)

        result = worker.deliver(sample_event)

        assert_equal "skipped", result.fetch(:status)
        assert_equal "route_mismatch", result.fetch(:reason)
        assert_equal 0, sink.delivered_events
        assert_equal 1, CheckpointStore.new(sqlite).count
      end
    end

    def test_delivers_and_checkpoints_successful_transaction_envelope
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = RecordingSink.new
        worker = build_worker(sqlite, sink: sink)
        envelope = FakeEnvelope.new(
          [sample_event.merge("source_position" => "0/1"), sample_event.merge("source_position" => "0/2")], "tx-1"
        )

        result = worker.deliver_transaction(envelope)
        checkpoint = CheckpointStore.new(sqlite).fetch(source_name: "local_mammoth", slot_name: "mammoth_prod")

        assert_equal "delivered", result.fetch(:status)
        assert_equal "transaction.committed", result.fetch(:payload_type)
        assert_equal "0/2", checkpoint.fetch("last_lsn")
        assert_equal envelope, sink.delivered_transactions.fetch(0)
      end
    end

    def test_checkpoint_helper_serializes_work
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        worker = build_worker(sqlite, sink: RecordingSink.new)

        worker.send(:checkpoint, sample_event, serializer: EventSerializer)

        checkpoint = CheckpointStore.new(sqlite).fetch(source_name: "local_mammoth", slot_name: "mammoth_prod")
        assert_equal "0/16F4A8B0", checkpoint.fetch("last_lsn")
      end
    end

    private

    def build_worker(sqlite, sink:, sleeper: ->(_seconds) {}, route_filter: nil, enabled: true)
      DeliveryWorker.new(
        sink: sink,
        checkpoint_store: CheckpointStore.new(sqlite),
        dead_letter_store: DeadLetterStore.new(sqlite),
        delivered_envelope_store: DeliveredEnvelopeStore.new(sqlite),
        source_name: "local_mammoth",
        slot_name: "mammoth_prod",
        publication_name: "mammoth_publication",
        max_attempts: 3,
        retry_schedule: [1, 5],
        sleeper: sleeper,
        route_filter: route_filter,
        enabled: enabled
      )
    end

    def sample_event
      {
        "event_id" => "event-1",
        "source" => "postgresql",
        "operation" => "insert",
        "namespace" => "public",
        "entity" => "orders",
        "source_position" => "0/16F4A8B0",
        "data" => { "id" => 1 }
      }
    end

    FakeEnvelope = Data.define(:events, :transaction_id)

    class RecordingSink
      attr_reader :name, :delivered_transactions, :delivered_events

      def initialize
        @name = "primary_webhook"
        @delivered_events = 0
        @delivered_transactions = []
      end

      def deliver(event)
        @delivered_events += 1
        { event_id: event.fetch("event_id"), destination: name, status: "delivered", http_status: 200 }
      end

      def deliver_transaction(envelope)
        @delivered_transactions << envelope
        { event_id: "transaction-1", payload_type: "transaction.committed", destination: name, status: "delivered",
          http_status: 200 }
      end
    end

    class FailingSink < RecordingSink
      def deliver(_event)
        raise DeliveryError, "boom"
      end
    end

    class FlakySink < RecordingSink
      def initialize(failures_before_success:)
        super()
        @failures_before_success = failures_before_success
        @attempts = 0
      end

      def deliver(event)
        @attempts += 1
        raise DeliveryError, "temporary" if @attempts <= @failures_before_success

        super
      end
    end
  end
end
