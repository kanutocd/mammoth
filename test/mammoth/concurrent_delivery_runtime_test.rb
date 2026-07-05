# frozen_string_literal: true

require "test_helper"

module Mammoth
  class ConcurrentDeliveryRuntimeTest < Minitest::Test
    def test_process_many_returns_empty_array_without_touching_pool_for_empty_items
      runtime = ConcurrentDeliveryRuntime.new(
        processor: RecordingProcessor.new,
        concurrency: 2,
        timeout: nil,
        preserve_order: false
      )

      assert_equal [], runtime.process_many([])
    ensure
      runtime&.shutdown
    end

    def test_process_many_delegates_to_cdc_concurrent_pool
      processor = RecordingProcessor.new
      runtime = ConcurrentDeliveryRuntime.new(processor: processor, concurrency: 2, timeout: 1, preserve_order: false)

      assert_equal [{ processed: "a" }, { processed: "b" }], runtime.process_many(%w[a b])
      refute CDC::Concurrent::ProcessorPool.last_options.fetch(:preserve_order)
      assert_equal 1, CDC::Concurrent::ProcessorPool.last_options.fetch(:timeout)
    ensure
      runtime&.shutdown
    end

    def test_raises_configuration_error_when_cdc_concurrent_is_unavailable
      runtime_class = Class.new(ConcurrentDeliveryRuntime) do
        private

        def build_pool
          raise LoadError, "cannot load such file -- cdc/concurrent"
        rescue LoadError => e
          raise ConfigurationError,
                "runtime.adapter=concurrent requires cdc-concurrent. Add `gem \"cdc-concurrent\"`. Original error: #{e.message}"
        end
      end

      error = assert_raises(ConfigurationError) do
        runtime_class.new(processor: RecordingProcessor.new, concurrency: 1, timeout: nil, preserve_order: true)
      end

      assert_match(/requires cdc-concurrent/, error.message)
    end

    def test_build_pool_wraps_load_error
      runtime_class = Class.new(ConcurrentDeliveryRuntime) do
        private

        def require(_feature)
          raise LoadError, "missing runtime"
        end
      end

      error = assert_raises(ConfigurationError) do
        runtime_class.new(processor: RecordingProcessor.new, concurrency: 1, timeout: nil, preserve_order: true)
      end

      assert_match(/missing runtime/, error.message)
    end

    def test_shutdown_is_noop_when_pool_does_not_support_shutdown
      runtime = ConcurrentDeliveryRuntime.allocate
      runtime.instance_variable_set(:@pool, Object.new)

      assert_nil runtime.shutdown
    end

    def test_shutdown_delegates_when_pool_supports_shutdown
      pool = ShutdownRecordingPool.new
      runtime = ConcurrentDeliveryRuntime.allocate
      runtime.instance_variable_set(:@pool, pool)

      assert_nil runtime.shutdown
      assert pool.shutdown_called
    end

    class RecordingProcessor
      def process(item)
        { processed: item }
      end
    end

    class ShutdownRecordingPool
      attr_reader :shutdown_called

      def shutdown
        @shutdown_called = true
      end
    end
  end
end
