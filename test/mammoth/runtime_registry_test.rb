# frozen_string_literal: true

require "test_helper"

module Mammoth
  class RuntimeRegistryTest < Minitest::Test
    def test_inline_and_concurrent_adapters_are_registered
      assert_same Runtimes::InlineAdapter, Runtimes::Registry.fetch("inline")
      assert_same Runtimes::ConcurrentAdapter, Runtimes::Registry.fetch("concurrent")
      assert_equal "adapter", Runtimes::Adapter.adapter_type
      assert_equal({ type: "adapter" }, Runtimes::Adapter.capabilities)
      assert_equal "custom", CustomAdapter.adapter_type
      assert_equal "inline", Runtimes::InlineAdapter.adapter_type
      assert_equal "concurrent", Runtimes::ConcurrentAdapter.adapter_type
    end

    def test_inline_adapter_processes_items
      processor = DeliveryProcessor.new(delivery_worker: RecordingWorker.new, delivery_unit: :event)
      runtime = Runtimes::Registry.build(
        "inline",
        processor: processor,
        concurrency: 1,
        timeout: nil,
        preserve_order: true
      )

      assert_equal [{ status: "ok", event_id: "event-1" }], runtime.process_many([{ "event_id" => "event-1" }])
      assert_nil runtime.shutdown
    end

    def test_unknown_runtime_fails_clearly
      error = assert_raises(ConfigurationError) { Runtimes::Registry.fetch("sidekiq") }

      assert_match(/unknown runtime adapter: sidekiq/, error.message)
    end

    class RecordingWorker
      def deliver(event)
        { status: "ok", event_id: event.fetch("event_id") }
      end
    end

    CustomAdapter = Class.new(Runtimes::Adapter)
  end
end
