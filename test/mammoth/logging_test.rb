# frozen_string_literal: true

require "json"
require "stringio"
require "test_helper"

module Mammoth
  class LoggingTest < Minitest::Test
    # rubocop:disable Metrics/AbcSize
    def test_emits_json_at_and_above_configured_level
      output = StringIO.new
      clock = -> { Time.utc(2026, 7, 24, 12, 0, 0) }
      logger = Logging::Logger.new(level: "info", output:, clock:)

      refute logger.debug("work_received", event_id: "hidden")
      assert logger.info("application_started", mammoth_name: "local")
      assert logger.warn("delivery_retry", attempt: 1, omitted: nil)
      assert logger.error("delivery_failed", error_class: "Mammoth::DeliveryError")

      records = output.string.lines.map { |line| JSON.parse(line) }
      severities = records.map { |record| record.fetch("severity") }
      assert_equal %w[info warn error], severities
      assert_equal "2026-07-24T12:00:00.000000Z", records.first.fetch("timestamp")
      assert_equal "mammoth", records.first.fetch("service")
      assert_equal "application_started", records.first.fetch("event")
      refute records.fetch(1).key?("omitted")
    end
    # rubocop:enable Metrics/AbcSize

    def test_builds_from_config_and_defaults_to_info
      output = StringIO.new
      config = Struct.new(:level) do
        def dig(*_keys) = level
      end

      assert_equal "error", Logging.build(config.new("error"), output:).level
      assert_equal "info", Logging.build(config.new(nil), output:).level
    end

    def test_rejects_an_unknown_level
      error = assert_raises(ConfigurationError) { Logging::Logger.new(level: "trace", output: StringIO.new) }

      assert_match(/unsupported logging level: trace/, error.message)
    end

    def test_null_logger_suppresses_every_level
      logger = Logging::NullLogger::INSTANCE

      refute logger.enabled?("debug")
      Logging::LEVELS.each_key { |severity| refute logger.public_send(severity, "event", value: 1) }
    end
  end
end
