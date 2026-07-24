# frozen_string_literal: true

require "json"
require "time"

module Mammoth
  # Container-friendly structured application logging.
  module Logging
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

      def debug(event, **context) = write("debug", event, context)
      def info(event, **context) = write("info", event, context)
      def warn(event, **context) = write("warn", event, context)
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
      INSTANCE = new

      def debug(_event, **_context) = false
      def info(_event, **_context) = false
      def warn(_event, **_context) = false
      def error(_event, **_context) = false
      def enabled?(_severity) = false
    end

    module_function

    def build(config, output: $stdout, clock: -> { Time.now.utc })
      Logger.new(level: config.dig("logging", "level") || "info", output:, clock:)
    end
  end
end
