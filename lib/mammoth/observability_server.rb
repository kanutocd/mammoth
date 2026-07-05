# frozen_string_literal: true

require "json"
require "webrick"

module Mammoth
  # Small HTTP server exposing Mammoth health, readiness, and metrics endpoints.
  #
  # The server is intentionally independent from the replication loop. Operators
  # may run it as a sidecar-like process or in a separate process that points at
  # the same SQLite operational database.
  class ObservabilityServer
    DEFAULT_HOST = "0.0.0.0"
    DEFAULT_PORT = 9393

    attr_reader :config, :host, :port, :sqlite_store, :logger, :server

    # @param config [Mammoth::Configuration] loaded configuration
    # @param host [String, nil] bind host override
    # @param port [Integer, nil] bind port override
    # @param sqlite_store [Mammoth::SQLiteStore, nil] optional operational store
    # @param logger [WEBrick::Log, nil] optional WEBrick logger
    def initialize(config, host: nil, port: nil, sqlite_store: nil, logger: nil)
      @config = config
      @host = host || config.dig("observability", "host") || DEFAULT_HOST
      @port = port || config.dig("observability", "port") || DEFAULT_PORT
      @sqlite_store = sqlite_store
      @logger = logger || WEBrick::Log.new($stderr, WEBrick::Log::WARN)
      @server = build_server
      mount_endpoints
    end

    # Start the blocking HTTP server.
    #
    # @return [void]
    def start
      server.start
    end

    # Stop the HTTP server.
    #
    # @return [void]
    def shutdown
      server.shutdown
    end

    private

    def build_server
      WEBrick::HTTPServer.new(
        BindAddress: host,
        Port: port,
        Logger: logger,
        AccessLog: []
      )
    end

    def mount_endpoints
      server.mount_proc("/healthz") { |_request, response| write_json(response, snapshot.health, status: 200) }
      server.mount_proc("/readyz") { |_request, response| write_readiness(response) }
      server.mount_proc("/metrics") { |_request, response| write_metrics(response) }
    end

    def write_readiness(response)
      payload = snapshot.readiness
      write_json(response, payload, status: payload.fetch(:status) == "ready" ? 200 : 503)
    end

    def write_metrics(response)
      response.status = 200
      response["Content-Type"] = "text/plain; version=0.0.4; charset=utf-8"
      response.body = snapshot.prometheus
    end

    def write_json(response, payload, status:)
      response.status = status
      response["Content-Type"] = "application/json"
      response.body = JSON.generate(payload)
    end

    def snapshot
      ObservabilitySnapshot.new(config, sqlite_store: sqlite_store)
    end
  end
end
