# frozen_string_literal: true

module Mammoth
  # Delivery runtime backed by CDC::Concurrent::ProcessorPool.
  #
  # Mammoth keeps a single upstream replication stream and delegates downstream
  # I/O fan-out to cdc-concurrent. This class is intentionally small so the
  # runtime boundary remains easy to test and replace.
  class ConcurrentDeliveryRuntime
    attr_reader :processor, :concurrency, :timeout, :preserve_order, :pool

    # @param processor [#process] delivery processor
    # @param concurrency [Integer] number of concurrent delivery workers
    # @param timeout [Numeric, nil] optional per-item timeout
    # @param preserve_order [Boolean] preserve output order when supported
    def initialize(processor:, concurrency:, timeout:, preserve_order:)
      @processor = processor
      @concurrency = concurrency
      @timeout = timeout
      @preserve_order = preserve_order
      @pool = build_pool
    end

    # Process many work items through cdc-concurrent.
    #
    # @param items [Array<Object>] CDC work units
    # @return [Array<Object>] processor results
    def process_many(items)
      return [] if items.empty?

      pool.process_many(items)
    end

    # Shutdown the underlying runtime when supported.
    #
    # @return [nil]
    def shutdown
      pool.shutdown if pool.respond_to?(:shutdown)
      nil
    end

    private

    def build_pool
      require "cdc/concurrent"
      CDC::Concurrent::ProcessorPool.new(processor:, concurrency:, timeout:, preserve_order:)
    rescue LoadError => e
      raise ConfigurationError,
            "runtime.adapter=concurrent requires cdc-concurrent. Add `gem \"cdc-concurrent\"`. Original error: #{e.message}"
    end
  end
end
