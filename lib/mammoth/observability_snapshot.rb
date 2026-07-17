# frozen_string_literal: true

require "time"

module Mammoth
  # Builds health, readiness, and metrics snapshots from Mammoth's operational
  # state and optional PostgreSQL slot-health provider.
  #
  # ObservabilitySnapshot is intentionally read-only. It does not start the
  # relay, mutate checkpoints, replay dead letters, or change PostgreSQL slot
  # state. An injected provider may perform read-only slot inspection. The
  # endpoints expose process, operational-state, and source status predictably.
  class ObservabilitySnapshot # rubocop:disable Metrics/ClassLength
    include ObservabilityMetrics

    attr_reader :config, :state_adapter, :clock, :dispatch_metrics, :slot_health_provider

    # @param config [Mammoth::Configuration] loaded configuration
    # @param state_adapter [Mammoth::OperationalState::Adapter, nil] operational state dependency
    # @param clock [#call] time source returning a Time-like object
    # @param dispatch_metrics [Mammoth::DispatchMetrics] dispatch counter registry
    # @param slot_health_provider [#slot_health, nil] PostgreSQL slot health dependency
    def initialize(config, state_adapter: nil, clock: -> { Time.now.utc }, dispatch_metrics: DispatchMetrics::INSTANCE,
                   slot_health_provider: nil)
      @config = config
      @state_adapter = state_adapter || OperationalState::Registry.build_configured(config)
      @clock = clock
      @dispatch_metrics = dispatch_metrics
      @slot_health_provider = slot_health_provider
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

      payload = {
        status: "ready",
        service: "mammoth",
        name: mammoth_name,
        operational_state: "ok",
        adapter: state_summary.fetch(:adapter),
        summary: state_summary,
        checked_at: checked_at
      }
      return payload unless slot_health_provider

      health = postgres_slot_health
      return postgres_unready_payload(health) unless health.ready?

      payload.merge(postgres_slot: health.summary)
    rescue ReplicationError => e
      postgres_error_payload(e)
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
      ) + dispatch_metric_lines + postgres_slot_metric_lines
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

    def postgres_unready_payload(health)
      {
        status: "unready",
        service: "mammoth",
        name: mammoth_name,
        operational_state: "ok",
        adapter: state_summary.fetch(:adapter),
        summary: state_summary,
        postgres_slot: health.summary,
        checked_at: checked_at
      }
    end

    def postgres_error_payload(error)
      {
        status: "unready",
        service: "mammoth",
        name: mammoth_name,
        operational_state: "ok",
        adapter: configured_adapter_name,
        postgres_slot: {
          ready: false,
          reason: "inspection failed",
          error_class: error.class.name,
          error_message: error.message
        },
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
      "#{(metric_headers + [metric_line("mammoth_up", 0)] + dispatch_metric_lines).join("\n")}\n"
    end

    def postgres_slot_metric_lines
      return [] unless slot_health_provider

      postgres_metric_lines(postgres_slot_health)
    rescue ReplicationError
      postgres_inspection_error_metric_lines
    end

    def postgres_slot_health
      slot_health_provider.slot_health
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
  end
end
