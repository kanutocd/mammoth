# frozen_string_literal: true

module Mammoth
  # CDC core observer that records Mammoth dispatch counters.
  class MetricsObserver < CDC::Core::Observer
    attr_reader :metrics

    # @param metrics [Mammoth::DispatchMetrics] dispatch counter registry
    def initialize(metrics: DispatchMetrics::INSTANCE)
      super()
      @metrics = metrics
    end

    # Record a dispatch attempt.
    #
    # @param event [Object] CDC work item
    # @return [Integer] updated counter
    def dispatch_started(event)
      record(self.class.started_metric_name, event)
    end

    # Record a successful dispatch.
    #
    # @param result [CDC::Core::ProcessorResult] processor result
    # @return [Integer] updated counter
    def dispatch_succeeded(result)
      record(self.class.succeeded_metric_name, result)
    end

    # Record a failed dispatch.
    #
    # @param result [CDC::Core::ProcessorResult] processor result
    # @return [Integer] updated counter
    def dispatch_failed(result)
      record(self.class.failed_metric_name, result)
    end

    # Record a skipped dispatch.
    #
    # @param result [CDC::Core::ProcessorResult] processor result
    # @return [Integer] updated counter
    def dispatch_skipped(result)
      record(self.class.skipped_metric_name, result)
    end

    private

    def record(name, payload)
      metrics.increment(name, CDC::Core::Observer.metric_tags(payload))
    end
  end
end
