# frozen_string_literal: true

require "time"

module Mammoth
  # Builds health, readiness, and metrics snapshots from Mammoth's local
  # operational state.
  #
  # ObservabilitySnapshot is intentionally read-only. It does not start the
  # relay, mutate checkpoints, replay dead letters, or inspect PostgreSQL. The
  # health and metrics endpoints use this object to expose Mammoth process and
  # SQLite operational-state status in a predictable format.
  class ObservabilitySnapshot
    attr_reader :config, :sqlite_store, :clock

    # @param config [Mammoth::Configuration] loaded configuration
    # @param sqlite_store [Mammoth::SQLiteStore, nil] optional operational store
    # @param clock [#call] time source returning a Time-like object
    def initialize(config, sqlite_store: nil, clock: -> { Time.now.utc })
      @config = config
      @sqlite_store = sqlite_store
      @clock = clock
    end

    # Build a liveness response.
    #
    # @return [Hash] health payload
    def health
      {
        status: "ok",
        service: "mammoth",
        name: mammoth_name,
        version: Mammoth::VERSION,
        checked_at: checked_at
      }
    end

    # Build a readiness response.
    #
    # @return [Hash] readiness payload
    def readiness
      store = operational_store
      store.bootstrap!

      {
        status: "ready",
        service: "mammoth",
        name: mammoth_name,
        sqlite: "ok",
        tables: store.tables,
        checked_at: checked_at
      }
    rescue Mammoth::Error, SQLite3::Exception => e
      {
        status: "unready",
        service: "mammoth",
        name: mammoth_name,
        sqlite: "error",
        error_class: e.class.name,
        error_message: e.message,
        checked_at: checked_at
      }
    end

    # Build a Prometheus text exposition document.
    #
    # @return [String] Prometheus metrics text
    def prometheus
      store = operational_store.bootstrap!
      checkpoint_store = CheckpointStore.new(store)
      dead_letter_store = DeadLetterStore.new(store)
      delivered_store = DeliveredEnvelopeStore.new(store)

      lines = metric_headers + aggregate_metric_lines(
        checkpoint_store: checkpoint_store,
        dead_letter_store: dead_letter_store,
        delivered_store: delivered_store
      ) + destination_metric_lines(dead_letter_store:, delivered_store:)
      "#{lines.join("\n")}\n"
    rescue Mammoth::Error, SQLite3::Exception
      "#{(metric_headers + [metric_line("mammoth_up", 0)]).join("\n")}\n"
    end

    private

    def aggregate_metric_lines(checkpoint_store:, dead_letter_store:, delivered_store:)
      [
        metric_line("mammoth_up", 1),
        metric_line("mammoth_checkpoints_total", checkpoint_store.count),
        metric_line("mammoth_dead_letters_total", dead_letter_store.count),
        metric_line("mammoth_dead_letters_pending_total", dead_letter_store.count(status: "pending")),
        metric_line("mammoth_dead_letters_resolved_total", dead_letter_store.count(status: "resolved")),
        metric_line("mammoth_dead_letters_ignored_total", dead_letter_store.count(status: "ignored")),
        metric_line("mammoth_delivered_envelopes_total", delivered_store.count)
      ]
    end

    def destination_metric_lines(dead_letter_store:, delivered_store:)
      destination_names.flat_map do |destination|
        [
          metric_line("mammoth_dead_letters_total", dead_letter_store.count(destination: destination),
                      destination: destination),
          metric_line("mammoth_dead_letters_pending_total",
                      dead_letter_store.count(status: "pending", destination: destination), destination: destination),
          metric_line("mammoth_dead_letters_resolved_total",
                      dead_letter_store.count(status: "resolved", destination: destination), destination: destination),
          metric_line("mammoth_dead_letters_ignored_total",
                      dead_letter_store.count(status: "ignored", destination: destination), destination: destination),
          metric_line("mammoth_delivered_envelopes_total", delivered_store.count(destination: destination),
                      destination: destination)
        ]
      end
    end

    def operational_store
      sqlite_store || SQLiteStore.connect(config.dig("sqlite", "path"))
    end

    def mammoth_name
      config.dig("mammoth", "name")
    end

    def destination_names
      destinations = config.data["destinations"]
      return destinations.map { |destination| destination.fetch("name") } if destinations

      [config.dig("webhook", "name")]
    end

    def checked_at
      clock.call.utc.iso8601
    end

    def metric_headers
      [
        "# HELP mammoth_up 1 when Mammoth operational state can be inspected, 0 otherwise.",
        "# TYPE mammoth_up gauge",
        "# HELP mammoth_checkpoints_total Number of checkpoint rows stored by Mammoth.",
        "# TYPE mammoth_checkpoints_total gauge",
        "# HELP mammoth_dead_letters_total Number of dead-letter rows stored by Mammoth.",
        "# TYPE mammoth_dead_letters_total gauge",
        "# HELP mammoth_dead_letters_pending_total Number of pending dead-letter rows.",
        "# TYPE mammoth_dead_letters_pending_total gauge",
        "# HELP mammoth_dead_letters_resolved_total Number of resolved dead-letter rows.",
        "# TYPE mammoth_dead_letters_resolved_total gauge",
        "# HELP mammoth_dead_letters_ignored_total Number of ignored dead-letter rows.",
        "# TYPE mammoth_dead_letters_ignored_total gauge",
        "# HELP mammoth_delivered_envelopes_total Number of delivered-envelope ledger rows.",
        "# TYPE mammoth_delivered_envelopes_total gauge"
      ]
    end

    def metric_line(name, value, destination: nil)
      labels = { "mammoth_name" => mammoth_name }
      labels["destination"] = destination if destination
      %(#{name}{#{labels.map { |label, label_value| %(#{label}="#{escape_label(label_value)}") }.join(",")}} #{Integer(value)})
    end

    def escape_label(value)
      value.to_s.gsub("\\", "\\\\").gsub('"', '\\"').gsub("\n", "\\n")
    end
  end
end
