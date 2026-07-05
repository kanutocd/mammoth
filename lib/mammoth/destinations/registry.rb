# frozen_string_literal: true

module Mammoth
  module Destinations
    # Registry for destination adapters.
    module Registry
      class << self
        # Register a destination adapter.
        #
        # @param name [String, Symbol] adapter name
        # @param adapter [Object] adapter class
        # @return [Object] registered adapter
        def register(name, adapter)
          registry.register(name, adapter)
        end

        # Fetch a destination adapter.
        #
        # @param name [String, Symbol] adapter name
        # @return [Object] adapter class
        def fetch(name)
          registry.fetch(name)
        end

        # Build a destination sink from config.
        #
        # @param destination [Hash] destination config
        # @param label [String] config label for errors
        # @return [Object] delivery sink
        def build(destination, label:)
          fetch(destination.fetch("type", "webhook")).build(destination, label: label)
        end

        # @return [Array<String>] registered destination adapter names
        def names
          registry.names
        end

        # @return [Mammoth::Registry] underlying registry
        def registry
          @registry ||= Mammoth::Registry.new("destination")
        end
      end
    end
  end
end
