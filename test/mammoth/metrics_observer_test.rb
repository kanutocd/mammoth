# frozen_string_literal: true

require "test_helper"

module Mammoth
  class MetricsObserverTest < Minitest::Test
    def setup
      @metrics = DispatchMetrics.new
      @observer = MetricsObserver.new(metrics: @metrics)
    end

    def test_records_all_canonical_dispatch_hooks
      success = CDC::Core::ProcessorResult.success("event")
      failure = CDC::Core::ProcessorResult.failure(
        DeliveryError.new("boom"),
        event: "event",
        retryable: false,
        processor: "Mammoth::DeliveryProcessor"
      )
      skipped = CDC::Core::ProcessorResult.skipped("event")

      @observer.dispatch_started("event")
      @observer.dispatch_succeeded(success)
      @observer.dispatch_failed(failure)
      @observer.dispatch_skipped(skipped)

      entries = @metrics.snapshot
      assert_equal CDC::Core::Observer::METRIC_NAMES.values.sort, entries.map { |entry| entry[:name] }.sort
      assert_failed_entry(entries)
    end

    def test_aggregates_equal_metric_and_tag_sets
      2.times { @observer.dispatch_started("event") }

      assert_equal 2, @metrics.snapshot.fetch(0).fetch(:value)
      assert_same @metrics, @metrics.reset!
      assert_empty @metrics.snapshot
    end

    private

    def assert_failed_entry(entries)
      failed = entries.find { |entry| entry[:name] == CDC::Core::Observer.failed_metric_name }
      assert_equal "failure", failed.fetch(:tags).fetch("status").to_s
      assert_equal "Mammoth::DeliveryProcessor", failed.fetch(:tags).fetch("processor")
      assert_equal 1, failed.fetch(:value)
    end
  end
end
