# frozen_string_literal: true

require "test_helper"

module Mammoth
  class DeliveryProcessorTest < Minitest::Test
    def test_processes_events_by_default
      worker = RecordingWorker.new
      processor = DeliveryProcessor.new(delivery_worker: worker)
      result = processor.process("event-1")

      assert_instance_of CDC::Core::ProcessorResult, result
      assert_predicate result, :success?
      assert_equal "event-1", result.event
      assert_equal({ kind: :event, work: "event-1" }, result.value)
      assert_equal "event", result.metadata[:delivery_unit]
    end

    def test_call_delegates_to_process
      worker = RecordingWorker.new
      processor = DeliveryProcessor.new(delivery_worker: worker)

      assert_equal({ kind: :event, work: "event-1" }, processor.call("event-1").value)
    end

    def test_declares_concurrent_safety_for_cdc_concurrent_processor_pool
      processor = DeliveryProcessor.new(delivery_worker: RecordingWorker.new)

      assert_kind_of CDC::Core::Processor, processor
      assert_predicate DeliveryProcessor, :concurrent_safe?
      assert_predicate DeliveryProcessor, :concurrent_safe
      assert_predicate processor, :concurrent_safe?
      assert_predicate processor, :concurrent_safe
      assert DeliveryProcessor.concurrent_safe!
    end

    def test_processes_transaction_envelopes_when_configured
      worker = RecordingWorker.new
      processor = DeliveryProcessor.new(delivery_worker: worker, delivery_unit: "transaction")
      result = processor.process("tx-1")

      assert_predicate result, :success?
      assert_equal({ kind: :transaction, work: "tx-1" }, result.value)
      assert_equal "transaction", result.metadata[:delivery_unit]
    end

    def test_maps_skipped_delivery_to_core_skipped_result
      processor = DeliveryProcessor.new(delivery_worker: ResultWorker.new(status: "skipped"))
      result = processor.process("event-1")

      assert_predicate result, :skipped?
      assert_equal "skipped", result.metadata[:delivery]["status"]
      assert_equal "Mammoth::DeliveryProcessor", result.metadata[:processor]
    end

    def test_maps_dead_lettered_delivery_to_non_retryable_core_failure
      processor = DeliveryProcessor.new(delivery_worker: ResultWorker.new(status: "dead_lettered"))
      result = processor.process("event-1")

      assert_predicate result, :failure?
      refute_predicate result, :retryable?
      assert_instance_of DeliveryError, result.error
      assert_equal "delivery completed with dead_lettered status", result.failure_reason
      assert_equal "dead_lettered", result.metadata[:delivery]["status"]
    end

    def test_maps_partial_fanout_to_non_retryable_core_failure
      processor = DeliveryProcessor.new(delivery_worker: ResultWorker.new(status: "fanout_partial"))
      result = processor.process("event-1")

      assert_predicate result, :failure?
      assert_equal "fanout_partial", result.metadata[:delivery]["status"]
    end

    def test_maps_delivery_errors_to_retryable_core_failure
      processor = DeliveryProcessor.new(delivery_worker: ErrorWorker.new(DeliveryError.new("temporary")))
      result = processor.process("event-1")

      assert_predicate result, :failure?
      assert_predicate result, :retryable?
      assert_equal "temporary", result.failure_reason
    end

    def test_maps_unexpected_errors_to_non_retryable_core_failure
      processor = DeliveryProcessor.new(delivery_worker: ErrorWorker.new(ArgumentError.new("invalid")))
      result = processor.process("event-1")

      assert_predicate result, :failure?
      refute_predicate result, :retryable?
      assert_equal "invalid", result.failure_reason
    end

    class RecordingWorker
      def deliver(work)
        { kind: :event, work: work }
      end

      def deliver_transaction(work)
        { kind: :transaction, work: work }
      end
    end

    class ResultWorker
      def initialize(status:)
        @status = status
      end

      def deliver(_work)
        { status: @status }
      end
    end

    class ErrorWorker
      def initialize(error)
        @error = error
      end

      def deliver(_work)
        raise @error
      end
    end
  end
end
