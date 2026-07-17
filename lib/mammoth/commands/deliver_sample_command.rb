# frozen_string_literal: true

require "json"

module Mammoth
  module Commands
    # Delivers one JSON event file through the configured local application.
    class DeliverSampleCommand
      attr_reader :config, :event_path, :output, :lifecycle_hooks

      # @param config [Mammoth::Configuration] loaded configuration
      # @param event_path [String] event JSON path
      # @param output [#puts] output stream
      # @param lifecycle_hooks [Mammoth::LifecycleHooks, Hash] local lifecycle callbacks
      def initialize(config, event_path:, output: $stdout, lifecycle_hooks: LifecycleHooks.new)
        @config = config
        @event_path = event_path
        @output = output
        @lifecycle_hooks = lifecycle_hooks
      end

      # @return [Integer] process-style status code
      def call
        raise ConfigurationError, "event JSON file not found: #{event_path}" unless File.file?(event_path)

        event = PersistedPayloadDeserializer.event(JSON.parse(File.read(event_path)))
        processed = Application.new(config, source: [event], lifecycle_hooks: lifecycle_hooks).start
        output.puts "Processed sample events: #{processed}"
        0
      rescue JSON::ParserError => e
        raise ConfigurationError, "invalid event JSON in #{event_path}: #{e.message}"
      end
    end
  end
end
