# frozen_string_literal: true

require "test_helper"

module Mammoth
  class DeliveryWorkerLedgerBranchEdgesTest < Minitest::Test
    def test_uses_injected_delivery_ledger
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        injected_ledger = DeliveredEnvelopeStore.new(sqlite)
        worker = build_worker(
          sqlite,
          sink: RecordingSink.new,
          delivered_envelope_store: injected_ledger
        )

        result = worker.deliver_transaction(FakeEnvelope.new([sample_event("0/INJECTED")], "tx-injected"))

        assert_equal "delivered", result.fetch(:status)
        assert_same injected_ledger, worker.delivered_envelope_store
        assert_equal 1, injected_ledger.count
      end
    end

    def test_uses_sink_class_name_when_sink_has_no_name
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        worker = build_worker(sqlite, sink: NamelessSink.new)

        result = worker.deliver_transaction(FakeEnvelope.new([sample_event("0/NAMELESS")], "tx-nameless"))
        row = DeliveredEnvelopeStore.new(sqlite).all.first

        assert_equal "delivered", result.fetch(:status)
        assert_includes row.fetch("destination_name"), "NamelessSink"
      end
    end

    def test_retry_schedule_falls_back_to_last_entry
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sleeps = []
        worker = build_worker(
          sqlite,
          sink: FailingSink.new,
          max_attempts: 3,
          retry_schedule: [0.25],
          sleeper: ->(seconds) { sleeps << seconds }
        )

        result = worker.deliver_transaction(FakeEnvelope.new([sample_event("0/RETRY")], "tx-retry"))

        assert_equal "dead_lettered", result.fetch(:status)
        assert_equal [0.25, 0.25], sleeps
        assert_equal 0, DeliveredEnvelopeStore.new(sqlite).count
      end
    end

    def test_event_without_event_id_still_builds_stable_key_from_source_position
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = RecordingSink.new
        worker = build_worker(sqlite, sink: sink)
        event = sample_event("0/NOEVENTID").tap { |payload| payload.delete("event_id") }

        first = worker.deliver(event)
        second = worker.deliver(event)

        assert_equal "delivered", first.fetch(:status)
        assert_equal "delivered", second.fetch(:status)
        refute second.fetch(:duplicate, false)
        assert_equal 2, sink.delivered_events.length
        assert_equal 2, DeliveredEnvelopeStore.new(sqlite).count
      end
    end

    private

    def build_worker(sqlite, sink:, delivered_envelope_store: nil, max_attempts: 2, retry_schedule: [0],
                     sleeper: ->(_seconds) {})
      delivered_envelope_store ||= DeliveredEnvelopeStore.new(sqlite)
      DeliveryWorker.new(
        sink: sink,
        checkpoint_store: CheckpointStore.new(sqlite),
        dead_letter_store: DeadLetterStore.new(sqlite),
        delivered_envelope_store: delivered_envelope_store,
        source_name: "local_mammoth",
        slot_name: "mammoth_prod",
        publication_name: "mammoth_publication",
        max_attempts: max_attempts,
        retry_schedule: retry_schedule,
        sleeper: sleeper
      )
    end

    def sample_event(source_position)
      {
        "event_id" => "event-#{source_position}",
        "source" => "postgresql",
        "operation" => "insert",
        "namespace" => "public",
        "entity" => "orders",
        "source_position" => source_position,
        "data" => { "id" => 1 }
      }
    end

    FakeEnvelope = Data.define(:events, :transaction_id)

    class RecordingSink
      attr_reader :name, :delivered_events, :delivered_transactions

      def initialize(name = "primary_webhook")
        @name = name
        @delivered_events = []
        @delivered_transactions = []
      end

      def deliver(event)
        delivered_events << event
        { event_id: event["event_id"] || "generated", destination: name, status: "delivered", http_status: 200 }
      end

      def deliver_transaction(envelope)
        delivered_transactions << envelope
        { event_id: "transaction-#{envelope.transaction_id}", payload_type: "transaction.committed", destination: name,
          status: "delivered", http_status: 200 }
      end
    end

    class NamelessSink
      attr_reader :delivered_transactions

      def initialize
        @delivered_transactions = []
      end

      def deliver_transaction(envelope)
        delivered_transactions << envelope
        { status: "delivered", http_status: 200 }
      end
    end

    class FailingSink < RecordingSink
      def deliver_transaction(_envelope)
        raise DeliveryError, "boom"
      end
    end
  end
end
