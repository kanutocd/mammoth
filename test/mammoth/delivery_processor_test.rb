# frozen_string_literal: true

require "test_helper"

module Mammoth
  class DeliveryProcessorTest < Minitest::Test
    def test_processes_events_by_default
      worker = RecordingWorker.new
      processor = DeliveryProcessor.new(delivery_worker: worker)

      assert_equal({ kind: :event, work: "event-1" }, processor.process("event-1"))
    end

    def test_processes_transaction_envelopes_when_configured
      worker = RecordingWorker.new
      processor = DeliveryProcessor.new(delivery_worker: worker, delivery_unit: "transaction")

      assert_equal({ kind: :transaction, work: "tx-1" }, processor.process("tx-1"))
    end

    class RecordingWorker
      def deliver(work)
        { kind: :event, work: work }
      end

      def deliver_transaction(work)
        { kind: :transaction, work: work }
      end
    end
  end
end
