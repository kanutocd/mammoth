# frozen_string_literal: true

require "json"
require "time"

module Mammoth
  # Container-friendly structured application logging.
  module Logging
    # Supported severity names mapped to their filtering priority.
    LEVELS = { "debug" => 0, "info" => 1, "warn" => 2, "error" => 3 }.freeze

    # Logger that emits one JSON object per line.
    class Logger
      attr_reader :level, :output, :clock

      def initialize(level:, output: $stdout, clock: -> { Time.now.utc })
        @level = level.to_s
        @output = output
        @clock = clock
        raise ConfigurationError, "unsupported logging level: #{@level}" unless LEVELS.key?(@level)
      end

      # Emit a debug event when debug logging is enabled.
      #
      # @param event [String, Symbol] stable event name
      # @param context [Hash] structured event fields
      # @return [Boolean] whether the event was emitted
      def debug(event, **context) = write("debug", event, context)

      # Emit an informational event when info logging is enabled.
      #
      # @param event [String, Symbol] stable event name
      # @param context [Hash] structured event fields
      # @return [Boolean] whether the event was emitted
      def info(event, **context) = write("info", event, context)

      # Emit a warning event when warn logging is enabled.
      #
      # @param event [String, Symbol] stable event name
      # @param context [Hash] structured event fields
      # @return [Boolean] whether the event was emitted
      def warn(event, **context) = write("warn", event, context)

      # Emit an error event.
      #
      # @param event [String, Symbol] stable event name
      # @param context [Hash] structured event fields
      # @return [Boolean] whether the event was emitted
      def error(event, **context) = write("error", event, context)

      def enabled?(severity)
        LEVELS.fetch(severity.to_s) >= LEVELS.fetch(level)
      end

      private

      def write(severity, event, context)
        return false unless enabled?(severity)

        output.puts JSON.generate(
          { timestamp: clock.call.utc.iso8601(6), severity:, service: "mammoth", event: }.merge(context.compact)
        )
        true
      end
    end

    # No-op logger used at injectable library boundaries.
    class NullLogger
      # Shared immutable no-op logger.
      INSTANCE = new

      # Suppress a debug event.
      #
      # @return [false]
      def debug(_event, **_context) = false

      # Suppress an informational event.
      #
      # @return [false]
      def info(_event, **_context) = false

      # Suppress a warning event.
      #
      # @return [false]
      def warn(_event, **_context) = false

      # Suppress an error event.
      #
      # @return [false]
      def error(_event, **_context) = false

      def enabled?(_severity) = false
    end

    module_function

    # Build the configured structured logger.
    #
    # @param config [Mammoth::Configuration, Hash] loaded Mammoth configuration
    # @param output [IO] destination for newline-delimited JSON
    # @param clock [#call] UTC-compatible time source
    # @return [Mammoth::Logging::Logger]
    def build(config, output: $stdout, clock: -> { Time.now.utc })
      Logger.new(level: config.dig("logging", "level") || "info", output:, clock:)
    end
  end
end
