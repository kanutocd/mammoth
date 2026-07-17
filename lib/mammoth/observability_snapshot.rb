# frozen_string_literal: true

require "time"

module Mammoth
  # Builds health, readiness, and metrics snapshots from Mammoth's local
  # operational state.
  #
  # ObservabilitySnapshot is intentionally read-only. It does not start the
  # relay, mutate checkpoints, replay dead letters, or inspect PostgreSQL. The
  # health and metrics endpoints use this object to expose Mammoth process and
  # operational-state adapter status in a predictable format.
  class ObservabilitySnapshot
    attr_reader :config, :state_adapter, :clock

    # @param config [Mammoth::Configuration] loaded configuration
    # @param state_adapter [Mammoth::OperationalState::Adapter, nil] operational state dependency
    # @param clock [#call] time source returning a Time-like object
    def initialize(config, state_adapter: nil, clock: -> { Time.now.utc })
      @config = config
      @state_adapter = state_adapter || OperationalState::Registry.build_configured(config)
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
      return unready_payload unless state_adapter.ready?

      {
        status: "ready",
        service: "mammoth",
        name: mammoth_name,
        operational_state: "ok",
        adapter: state_summary.fetch(:adapter),
        summary: state_summary,
        checked_at: checked_at
      }
    rescue Mammoth::Error => e
      adapter_error_payload(e)
    end

    # Build a Prometheus text exposition document.
    #
    # @return [String] Prometheus metrics text
    def prometheus
      return down_metrics unless state_adapter.ready?

      lines = metric_headers + aggregate_metric_lines(
        checkpoint_store: state_adapter.checkpoint_store,
        dead_letter_store: state_adapter.dead_letter_store,
        delivered_store: state_adapter.delivered_envelope_store
      ) + destination_metric_lines(
        dead_letter_store: state_adapter.dead_letter_store,
        delivered_store: state_adapter.delivered_envelope_store
      )
      "#{lines.join("\n")}\n"
    rescue Mammoth::Error
      down_metrics
    end

    private

    def adapter_error_payload(error)
      {
        status: "unready",
        service: "mammoth",
        name: mammoth_name,
        operational_state: "error",
        adapter: configured_adapter_name,
        error_class: error.class.name,
        error_message: error.message,
        checked_at: checked_at
      }
    end

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

    def unready_payload
      {
        status: "unready",
        service: "mammoth",
        name: mammoth_name,
        operational_state: "error",
        adapter: configured_adapter_name,
        checked_at: checked_at
      }
    end

    def down_metrics
      "#{(metric_headers + [metric_line("mammoth_up", 0)]).join("\n")}\n"
    end

    def state_summary
      @state_summary ||= state_adapter.summary
    end

    def configured_adapter_name
      config.dig("operational_state", "adapter") || "sqlite"
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
