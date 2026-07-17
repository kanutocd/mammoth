# frozen_string_literal: true

require "test_helper"

module Mammoth
  class DeliveryWorkerLedgerTest < Minitest::Test
    def test_skips_duplicate_transaction_delivery_but_advances_checkpoint
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = RecordingSink.new
        worker = build_worker(sqlite, sink: sink)
        envelope = transaction_envelope("0/AAA", "tx-1")

        first = worker.deliver_transaction(envelope)
        second = worker.deliver_transaction(envelope)
        checkpoint = CheckpointStore.new(sqlite).fetch(source_name: "local_mammoth", slot_name: "mammoth_prod")
        ledger = DeliveredEnvelopeStore.new(sqlite)

        assert_equal "delivered", first.fetch(:status)
        assert_equal "skipped", second.fetch(:status)
        assert second.fetch(:duplicate)
        assert_equal 1, sink.delivered_transactions.length
        assert_equal 1, ledger.count
        assert_equal "0/AAA", checkpoint.fetch("last_lsn")
      end
    end

    def test_redelivers_same_transaction_to_different_destination
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        envelope = transaction_envelope("0/BBB", "tx-2")
        primary = RecordingSink.new("primary_webhook")
        secondary = RecordingSink.new("secondary_webhook")

        build_worker(sqlite, sink: primary).deliver_transaction(envelope)
        build_worker(sqlite, sink: secondary).deliver_transaction(envelope)

        assert_equal 1, primary.delivered_transactions.length
        assert_equal 1, secondary.delivered_transactions.length
        assert_equal 2, DeliveredEnvelopeStore.new(sqlite).count
      end
    end

    def test_duplicate_event_delivery_is_skipped_by_event_id_and_source_position
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = RecordingSink.new
        worker = build_worker(sqlite, sink: sink)
        event = sample_event("0/CCC")

        first = worker.deliver(event)
        second = worker.deliver(event)

        assert_equal "delivered", first.fetch(:status)
        assert_equal "skipped", second.fetch(:status)
        assert second.fetch(:duplicate)
        assert_equal 1, sink.delivered_events.length
        assert_equal 1, DeliveredEnvelopeStore.new(sqlite).count
      end
    end

    def test_failed_delivery_does_not_record_ledger_entry
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        worker = build_worker(sqlite, sink: FailingSink.new, sleeper: ->(_seconds) {})

        result = worker.deliver_transaction(transaction_envelope("0/DDD", "tx-failed"))

        assert_equal "dead_lettered", result.fetch(:status)
        assert_equal 0, DeliveredEnvelopeStore.new(sqlite).count
      end
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
        max_attempts: 2,
        retry_schedule: [1],
        sleeper: sleeper
      )
    end

    def sample_event(source_position)
      core_event(event_id: "event-#{source_position}", source_position: source_position)
    end

    def transaction_envelope(source_position, transaction_id)
      core_envelope(
        events: [sample_event(source_position)],
        transaction_id: transaction_id
      )
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

    class FailingSink < RecordingSink
      def deliver_transaction(_envelope)
        raise DeliveryError, "boom"
      end
    end
  end
end
