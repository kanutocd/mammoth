# frozen_string_literal: true

module Mammoth
  # Reports local Mammoth capabilities without inspecting private internals.
  class Capabilities
    # Built-in OSS data-plane feature capabilities.
    FEATURES = %w[
      checkpointing
      delivery_ledger
      dead_letters
      replay
      health
      metrics
      routing
      fanout
    ].freeze

    attr_reader :config

    # @param config [Mammoth::Configuration] loaded configuration
    def initialize(config)
      @config = config
    end

    # @param config [Mammoth::Configuration] loaded configuration
    # @return [Hash] JSON-friendly capabilities
    def self.call(config)
      new(config).to_h
    end

    # @return [Hash] JSON-friendly capabilities
    def to_h
      {
        operational_state: operational_state_adapter,
        destinations: destination_types,
        runtimes: Runtimes::Registry.names,
        runtime: runtime_adapter,
        features: FEATURES
      }
    end

    private

    def operational_state_adapter
      config.dig("operational_state", "adapter") || "sqlite"
    end

    def runtime_adapter
      config.dig("runtime", "adapter") || "inline"
    end

    def destination_types
      destinations = config.data["destinations"]
      return [config.dig("webhook", "type") || "webhook"] unless destinations

      destinations.map { |destination| destination.fetch("type", "webhook") }.uniq.sort
    end
  end
end
