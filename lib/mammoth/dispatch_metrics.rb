# frozen_string_literal: true

module Mammoth
  # Thread-safe in-process counters populated by Mammoth's CDC core observer.
  #
  # The registry deliberately stores CDC core metric names and tags. Rendering
  # those counters for a specific backend remains an observability concern.
  class DispatchMetrics
    # Create an empty dispatch metric registry.
    def initialize
      @mutex = Mutex.new
      @counters = Hash.new(0)
    end

    # Process-wide dispatch metrics used by the default observer and snapshot.
    INSTANCE = new

    # Increment a canonical CDC core metric.
    #
    # @param name [String] canonical CDC core metric name
    # @param tags [Hash] canonical metric tags
    # @return [Integer] updated counter value
    def increment(name, tags = {})
      key = [name.to_s.freeze, normalized_tags(tags)]
      @mutex.synchronize { @counters[key] += 1 }
    end

    # Return an immutable point-in-time copy of all counters.
    #
    # @return [Array<Hash>] metric entries with name, tags, and value
    def snapshot
      @mutex.synchronize do
        @counters.map do |(name, tags), value|
          { name: name, tags: tags.to_h, value: value }
        end
      end
    end

    # Clear all counters.
    #
    # Intended for process lifecycle management and isolated tests.
    #
    # @return [self] cleared registry
    def reset!
      @mutex.synchronize { @counters.clear }
      self
    end

    private

    def normalized_tags(tags)
      tags.to_h.transform_keys(&:to_s).sort_by(&:first).freeze
    end
  end
end
