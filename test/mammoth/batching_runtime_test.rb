# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Runtimes
    class BatchingRuntimeTest < Minitest::Test
      def test_owns_full_and_partial_batch_submission
        selected_runtime = RecordingRuntime.new
        runtime = BatchingRuntime.new(runtime: selected_runtime, batch_size: 2)

        assert_equal [], runtime.process("event-1")
        assert_equal %w[processed-event-1 processed-event-2], runtime.process("event-2")
        assert_equal [], runtime.process("event-3")
        assert_equal ["processed-event-3"], runtime.flush
        assert_equal [%w[event-1 event-2], ["event-3"]], selected_runtime.batches
        assert_equal [], runtime.flush
      end

      def test_process_many_delegates_without_changing_buffer
        selected_runtime = RecordingRuntime.new
        runtime = BatchingRuntime.new(runtime: selected_runtime, batch_size: 3)
        runtime.process("buffered")

        assert_equal ["processed-immediate"], runtime.process_many(["immediate"])
        assert_equal ["buffered"], runtime.buffer
      end

      def test_shutdown_flushes_and_delegates_lifecycle
        selected_runtime = RecordingRuntime.new
        runtime = BatchingRuntime.new(runtime: selected_runtime, batch_size: 2)
        runtime.process("event")

        assert_nil runtime.shutdown
        assert_equal [["event"]], selected_runtime.batches
        assert selected_runtime.shutdown?
      end

      def test_shutdown_supports_runtime_without_lifecycle_hook
        runtime = BatchingRuntime.new(runtime: ->(items) { items }, batch_size: 1)
        runtime.runtime.define_singleton_method(:process_many) { |items| call(items) }

        assert_nil runtime.shutdown
      end

      class RecordingRuntime
        attr_reader :batches

        def initialize
          @batches = []
          @shutdown = false
        end

        def process_many(items)
          batches << items
          items.map { |item| "processed-#{item}" }
        end

        def shutdown
          @shutdown = true
        end

        def shutdown?
          @shutdown
        end
      end
    end
  end
end
