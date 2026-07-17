# frozen_string_literal: true

module Mammoth
  # Adapter object used by CDC::Concurrent::ProcessorPool.
  #
  # The processor keeps cdc-concurrent integration narrow: cdc-concurrent owns
  # I/O-heavy fan-out mechanics, while DeliveryWorker owns Mammoth relay
  # semantics such as retries, dead letters, and checkpoint writes.
  class DeliveryProcessor < CDC::Core::Processor
    @concurrent_safe = false

    class << self
      # Mark this processor as safe for CDC::Concurrent::ProcessorPool.
      #
      # DeliveryProcessor itself is intentionally stateless after initialization;
      # per-delivery retry, dead-letter, and checkpoint behavior remains owned by
      # the injected DeliveryWorker.
      #
      # @return [true]
      def concurrent_safe!
        @concurrent_safe = true
      end

      # @return [Boolean] true when this processor has explicitly opted in to
      #   cdc-concurrent execution.
      def concurrent_safe?
        @concurrent_safe == true
      end

      alias concurrent_safe concurrent_safe?
    end

    concurrent_safe!

    attr_reader :delivery_worker, :delivery_unit

    # @param delivery_worker [Mammoth::DeliveryWorker] relay-aware delivery worker
    # @param delivery_unit [String, Symbol] event or transaction
    def initialize(delivery_worker:, delivery_unit: :event)
      super()
      @delivery_worker = delivery_worker
      @delivery_unit = delivery_unit.to_sym
    end

    # @return [Boolean] true when this processor instance is safe for concurrent execution.
    def concurrent_safe?
      self.class.concurrent_safe?
    end

    alias concurrent_safe concurrent_safe?

    # Process one work item from CDC::Concurrent::ProcessorPool.
    #
    # @param work [Object] event or transaction envelope
    # @return [CDC::Core::ProcessorResult] normalized processor result
    def call(work)
      process(work)
    end

    # Process one work item using the configured delivery unit.
    #
    # @param work [Object] event or transaction envelope
    # @return [CDC::Core::ProcessorResult] normalized processor result
    def process(work)
      summary = deliver(work)
      build_result(work, summary)
    rescue StandardError => e
      failure_result(work, e, retryable: e.is_a?(DeliveryError))
    end

    private

    def deliver(work)
      return delivery_worker.deliver_transaction(work) if delivery_unit == :transaction

      delivery_worker.deliver(work)
    end

    def build_result(work, summary)
      case summary[:status].to_s
      when "skipped"
        CDC::Core::ProcessorResult.skipped(work, metadata: result_metadata(summary))
      when "dead_lettered", "fanout_partial"
        failure_result(work, DeliveryError.new(failure_reason(summary)), retryable: false, summary: summary)
      else
        CDC::Core::ProcessorResult.success(work, value: summary, metadata: result_metadata(summary))
      end
    end

    def failure_result(work, error, retryable:, summary: nil)
      CDC::Core::ProcessorResult.failure(
        error,
        event: work,
        reason: error.message,
        retryable: retryable,
        processor: self.class.name,
        metadata: result_metadata(summary)
      )
    end

    def failure_reason(summary)
      "delivery completed with #{summary.fetch(:status)} status"
    end

    def result_metadata(summary)
      metadata = { processor: self.class.name, delivery_unit: delivery_unit.to_s }
      metadata[:delivery] = summary if summary
      metadata
    end
  end
end
