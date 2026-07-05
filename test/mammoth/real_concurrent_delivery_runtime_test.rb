# frozen_string_literal: true

require "open3"
require "rbconfig"
require "test_helper"

module Mammoth
  class RealConcurrentDeliveryRuntimeTest < Minitest::Test
    def test_real_cdc_concurrent_runtime_overlaps_delivery_work
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        "-Ilib",
        "-e",
        real_concurrency_script
      )

      assert status.success?, stderr
      assert_match(/max_active=4/, stdout)
      assert_match(/results=4/, stdout)
    end

    private

    def real_concurrency_script
      <<~RUBY
        require "async"
        require "mammoth"

        class OverlapWorker
          attr_reader :max_active

          def initialize
            @active = 0
            @max_active = 0
            @delivered = []
          end

          def deliver(event)
            @active += 1
            @max_active = [@max_active, @active].max
            Async::Task.current.sleep(0.05)
            @delivered << event.fetch("event_id")
            { status: "delivered", event_id: event.fetch("event_id") }
          ensure
            @active -= 1
          end
        end

        worker = OverlapWorker.new
        processor = Mammoth::DeliveryProcessor.new(delivery_worker: worker)
        runtime = Mammoth::ConcurrentDeliveryRuntime.new(
          processor: processor,
          concurrency: 4,
          timeout: nil,
          preserve_order: true
        )
        events = Array.new(4) { |index| { "event_id" => "event-\#{index}" } }

        results = runtime.process_many(events)
        runtime.shutdown

        unless results.all?(&:success?)
          warn results.map(&:to_h).inspect
          exit 1
        end

        puts "max_active=\#{worker.max_active}"
        puts "results=\#{results.length}"
      RUBY
    end
  end
end
