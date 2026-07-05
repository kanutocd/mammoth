# frozen_string_literal: true

module Mammoth
  # Small explicit registry for built-in and extension-provided adapters.
  class Registry
    attr_reader :namespace, :entries

    # @param namespace [String] human-readable registry name for errors
    def initialize(namespace)
      @namespace = namespace
      @entries = {}
    end

    # Register an adapter under a stable name.
    #
    # @param name [String, Symbol] adapter name
    # @param adapter [Object] adapter object or class
    # @return [Object] registered adapter
    def register(name, adapter)
      key = normalize_name(name)
      raise ConfigurationError, "#{namespace} adapter already registered: #{key}" if entries.key?(key)

      entries[key] = adapter
    end

    # Fetch a registered adapter.
    #
    # @param name [String, Symbol] adapter name
    # @return [Object] registered adapter
    def fetch(name)
      key = normalize_name(name)
      entries.fetch(key) { raise ConfigurationError, "unknown #{namespace} adapter: #{key}" }
    end

    # @return [Array<String>] registered adapter names
    def names
      entries.keys.sort
    end

    private

    def normalize_name(name)
      name.to_s
    end
  end
end
