# frozen_string_literal: true

require "test_helper"

module Mammoth
  class FanoutDeliveryWorkerTest < Minitest::Test
    def test_delivers_event_to_each_destination
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        primary = RecordingSink.new("primary_webhook")
        secondary = RecordingSink.new("audit_webhook")
        worker = FanoutDeliveryWorker.new([
                                            build_worker(sqlite, sink: primary),
                                            build_worker(sqlite, sink: secondary)
                                          ])

        result = worker.deliver(sample_event("0/fanout"))

        assert_equal "fanout_delivered", result.fetch(:status)
        assert_equal 2, result.fetch(:delivered)
        assert_equal 1, primary.delivered_events.length
        assert_equal 1, secondary.delivered_events.length
        assert_equal 2, DeliveredEnvelopeStore.new(sqlite).count
      end
    end

    def test_continues_after_one_destination_dead_letters
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        healthy = RecordingSink.new("healthy_webhook")
        worker = FanoutDeliveryWorker.new([
                                            build_worker(sqlite, sink: failing_sink, sleeper: ->(_seconds) {}),
                                            build_worker(sqlite, sink: healthy)
                                          ])

        envelope = core_envelope(
          events: [PersistedPayloadDeserializer.event(sample_event("0/partial"))],
          transaction_id: "tx-partial"
        )
        result = worker.deliver_transaction(envelope)

        assert_partial_fanout(result)
        assert_equal 1, healthy.delivered_transactions.length
        assert_equal 1, DeadLetterStore.new(sqlite).count(status: "pending")
        assert_equal 1, DeliveredEnvelopeStore.new(sqlite).count
      end
    end

    def test_delivers_to_one_named_destination_for_replay
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        primary = RecordingSink.new("primary_webhook")
        secondary = RecordingSink.new("audit_webhook")
        worker = FanoutDeliveryWorker.new([
                                            build_worker(sqlite, sink: primary),
                                            build_worker(sqlite, sink: secondary)
                                          ])

        result = worker.deliver_to("audit_webhook", sample_event("0/replay"))

        assert_equal "delivered", result.fetch(:status)
        assert_equal 0, primary.delivered_events.length
        assert_equal 1, secondary.delivered_events.length
        assert_equal 1, DeliveredEnvelopeStore.new(sqlite).count
      end
    end

    def test_named_destination_replay_rejects_missing_destination
      worker = FanoutDeliveryWorker.new([build_worker(SQLiteStore.connect(":memory:").bootstrap!,
                                                      sink: RecordingSink.new)])

      error = assert_raises(ConfigurationError) { worker.deliver_to("missing_webhook", sample_event("0/missing")) }

      assert_match(/destination not configured/, error.message)
    end

    def test_requires_at_least_one_destination_worker
      error = assert_raises(ConfigurationError) { FanoutDeliveryWorker.new([]) }

      assert_match(/at least one destination/, error.message)
    end

    private

    def build_worker(sqlite, sink:, sleeper: ->(_seconds) {})
      DeliveryWorker.new(
        sink: sink,
        checkpoint_store: CheckpointStore.new(sqlite),
        dead_letter_store: DeadLetterStore.new(sqlite),
        delivered_envelope_store: DeliveredEnvelopeStore.new(sqlite),
        source_name: "local_mammoth",
        slot_name: "mammoth_prod",
        publication_name: "mammoth_publication",
        max_attempts: 1,
        retry_schedule: [1],
        sleeper: sleeper
      )
    end

    def sample_event(source_position)
      core_event(event_id: "event-#{source_position}", source_position: source_position)
    end

    def assert_partial_fanout(result)
      assert_equal "fanout_partial", result.fetch(:status)
      assert_equal 1, result.fetch(:dead_lettered)
      assert_equal 1, result.fetch(:delivered)
    end

    class RecordingSink
      attr_reader :name, :delivered_events, :delivered_transactions

      def initialize(name = "primary_webhook")
        @name = name
        @delivered_events = []
        @delivered_transactions = []
      end

      def deliver(event)
        delivered_events << event
        { event_id: EventSerializer.call(event).fetch("event_id"), destination: name, status: "delivered",
          http_status: 200 }
      end

      def deliver_transaction(envelope)
        delivered_transactions << envelope
        { event_id: "transaction-#{envelope.transaction_id}", payload_type: "transaction.committed", destination: name,
          status: "delivered", http_status: 200 }
      end
    end

    def failing_sink
      Class.new(RecordingSink) do
        def initialize
          super("failing_webhook")
        end

        def deliver_transaction(_envelope)
          raise DeliveryError, "boom"
        end
      end.new
    end
  end
end
