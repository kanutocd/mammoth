# frozen_string_literal: true

require "json"
require "net/http"
require "test_helper"

module Mammoth
  class ObservabilityServerTest < Minitest::Test
    # rubocop:disable Metrics/AbcSize
    def test_exposes_health_readiness_and_metrics_endpoints
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db"))
        config = Configuration.load(write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: store.path)))
        server = ObservabilityServer.new(config, host: "127.0.0.1", port: 0, sqlite_store: store, logger: quiet_logger)
        thread = Thread.new { server.start }
        port = server.server.config.fetch(:Port)

        health = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/healthz"))
        ready = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/readyz"))
        metrics = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/metrics"))

        assert_equal "200", health.code
        assert_equal "ok", JSON.parse(health.body).fetch("status")
        assert_equal "200", ready.code
        assert_equal "ready", JSON.parse(ready.body).fetch("status")
        assert_equal "200", metrics.code
        assert_match(/mammoth_up\{mammoth_name="local_mammoth"\} 1/, metrics.body)
      ensure
        server&.shutdown
        thread&.join
      end
    end
    # rubocop:enable Metrics/AbcSize

    def test_uses_observability_config_defaults
      with_temp_dir do |dir|
        config_path = write_file(
          File.join(dir, "mammoth.yml"),
          "#{minimal_config(sqlite_path: File.join(dir, "mammoth.db"))}\nobservability:\n  host: 127.0.0.1\n  port: 9595\n"
        )
        server = ObservabilityServer.new(Configuration.load(config_path), logger: quiet_logger)

        assert_equal "127.0.0.1", server.host
        assert_equal 9595, server.port
      ensure
        server&.shutdown
      end
    end

    private

    def quiet_logger
      WEBrick::Log.new(File::NULL)
    end
  end
end
