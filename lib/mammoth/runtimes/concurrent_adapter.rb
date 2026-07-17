# frozen_string_literal: true

module Mammoth
  module Runtimes
    # Runtime adapter backed by Mammoth's existing cdc-concurrent wrapper.
    class ConcurrentAdapter < Adapter
      class << self
        # @return [String] adapter type name
        def adapter_type
          "concurrent"
        end

        # Build a concurrent runtime adapter.
        #
        # @param processor [#process] delivery processor
        # @param concurrency [Integer] worker count
        # @param timeout [Numeric, nil] optional timeout
        # @param preserve_order [Boolean] preserve ordering when supported
        # @param observer [CDC::Core::Observer] dispatch lifecycle observer
        # @return [Mammoth::ConcurrentDeliveryRuntime]
        def build(processor:, concurrency:, timeout:, preserve_order:, observer: CDC::Core::Observer.new)
          ConcurrentDeliveryRuntime.new(
            processor: processor,
            concurrency: concurrency,
            timeout: timeout,
            preserve_order: preserve_order,
            observer: observer
          )
        end
      end
    end
  end
end
