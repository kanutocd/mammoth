# frozen_string_literal: true

module Mammoth
  module Runtimes
    # Adds configured batch submission to a selected delivery runtime.
    #
    # Application streams one work item at a time into this runtime boundary.
    # BatchingRuntime owns accumulation and submits complete or final partial
    # batches through the selected adapter runtime's #process_many contract.
    class BatchingRuntime
      attr_reader :runtime, :batch_size, :buffer

      # @param runtime [#process_many] selected delivery runtime
      # @param batch_size [Integer] maximum work items submitted together
      def initialize(runtime:, batch_size:)
        @runtime = runtime
        @batch_size = batch_size
        @buffer = []
      end

      # Buffer one work item and submit a full batch when ready.
      #
      # @param work [CDC::Core::ChangeEvent, CDC::Core::TransactionEnvelope] core work item
      # @return [Array] processor results when a batch is submitted, otherwise an empty array
      def process(work)
        buffer << work
        return [] if buffer.size < batch_size

        flush
      end

      # Submit work immediately without changing the buffered stream.
      #
      # @param items [Array] work items
      # @return [Array] processor results
      def process_many(items)
        runtime.process_many(items)
      end

      # Submit the final partial batch.
      #
      # @return [Array] processor results, or an empty array when no work is buffered
      def flush
        return [] if buffer.empty?

        runtime.process_many(buffer.shift(buffer.size))
      end

      # Flush pending work and shut down the selected runtime when supported.
      #
      # @return [nil]
      def shutdown
        flush
        runtime.shutdown if runtime.respond_to?(:shutdown)
        nil
      end
    end
  end
end
