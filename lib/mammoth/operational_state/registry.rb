# frozen_string_literal: true

module Mammoth
  module OperationalState
    # Registry for operational state adapters.
    module Registry
      class << self
        # Register an operational state adapter.
        #
        # @param name [String, Symbol] adapter name
        # @param adapter [Object] adapter class
        # @return [Object] registered adapter
        def register(name, adapter)
          registry.register(name, adapter)
        end

        # Fetch an operational state adapter.
        #
        # @param name [String, Symbol] adapter name
        # @return [Object] adapter class
        def fetch(name)
          registry.fetch(name)
        end

        # Build an operational state adapter from config.
        #
        # @param name [String, Symbol] adapter name
        # @param config [Mammoth::Configuration] loaded configuration
        # @return [Mammoth::OperationalState::Adapter] adapter instance
        def build(name, config)
          fetch(name).from_config(config)
        end

        # Build the operational-state adapter selected by configuration.
        #
        # @param config [Mammoth::Configuration] loaded configuration
        # @return [Mammoth::OperationalState::Adapter] adapter instance
        def build_configured(config)
          build(config.dig("operational_state", "adapter") || "sqlite", config)
        end

        # @return [Array<String>] registered operational state adapter names
        def names
          registry.names
        end

        # @return [Mammoth::Registry] underlying registry
        def registry
          @registry ||= Mammoth::Registry.new("operational_state")
        end
      end
    end
  end
end
