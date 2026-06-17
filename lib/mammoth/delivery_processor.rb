# frozen_string_literal: true

module Mammoth
  # Adapter object used by CDC::Concurrent::ProcessorPool.
  #
  # The processor keeps cdc-concurrent integration narrow: cdc-concurrent owns
  # I/O-heavy fan-out mechanics, while DeliveryWorker owns Mammoth relay
  # semantics such as retries, dead letters, and checkpoint writes.
  class DeliveryProcessor
    attr_reader :delivery_worker, :delivery_unit

    # @param delivery_worker [Mammoth::DeliveryWorker] relay-aware delivery worker
    # @param delivery_unit [String, Symbol] event or transaction
    def initialize(delivery_worker:, delivery_unit: :event)
      @delivery_worker = delivery_worker
      @delivery_unit = delivery_unit.to_sym
    end

    # Process one work item from CDC::Concurrent::ProcessorPool.
    #
    # @param work [Object] event or transaction envelope
    # @return [Hash] delivery summary
    def process(work)
      case delivery_unit
      when :transaction
        delivery_worker.deliver_transaction(work)
      else
        delivery_worker.deliver(work)
      end
    end
  end
end
