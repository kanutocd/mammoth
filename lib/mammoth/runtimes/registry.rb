# frozen_string_literal: true

module Mammoth
  module Runtimes
    # Registry for delivery runtime adapters.
    module Registry
      class << self
        # Register a runtime adapter.
        #
        # @param name [String, Symbol] adapter name
        # @param adapter [Object] adapter class
        # @return [Object] registered adapter
        def register(name, adapter)
          registry.register(name, adapter)
        end

        # Fetch a runtime adapter.
        #
        # @param name [String, Symbol] adapter name
        # @return [Object] adapter class
        def fetch(name)
          registry.fetch(name)
        end

        # Build a runtime adapter.
        #
        # @param name [String, Symbol] adapter name
        # @param options [Hash] adapter-specific build options
        # @return [Object] runtime adapter
        def build(name, **options)
          fetch(name).build(**options)
        end

        # @return [Array<String>] registered runtime adapter names
        def names
          registry.names
        end

        # @return [Mammoth::Registry] underlying registry
        def registry
          @registry ||= Mammoth::Registry.new("runtime")
        end
      end
    end
  end
end
