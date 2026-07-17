# frozen_string_literal: true

module Mammoth
  # PostgreSQL slot-specific Prometheus formatting helpers.
  module PostgresObservabilityMetrics
    # Metric names and help text for PostgreSQL replication-slot gauges.
    POSTGRES_METRICS = {
      "mammoth_postgres_slot_inspection_up" => "1 when PostgreSQL slot inspection succeeds.",
      "mammoth_postgres_slot_present" => "1 when the configured replication slot exists.",
      "mammoth_postgres_slot_ready" => "1 when the configured slot is healthy and active.",
      "mammoth_postgres_slot_active" => "1 when PostgreSQL reports the slot as active.",
      "mammoth_postgres_slot_retained_wal_bytes" => "WAL retained from the slot restart LSN.",
      "mammoth_postgres_slot_safe_wal_size_bytes" => "WAL bytes that may be written before the slot risks loss.",
      "mammoth_postgres_slot_wal_status" => "Current PostgreSQL WAL retention status for the slot.",
      "mammoth_postgres_slot_invalidated" => "1 when PostgreSQL reports invalidation or conflict.",
      "mammoth_postgres_slot_inactive_since_timestamp_seconds" => "Unix timestamp when the slot became inactive.",
      "mammoth_postgres_slot_restart_lsn_bytes" => "Numeric PostgreSQL restart LSN.",
      "mammoth_postgres_slot_confirmed_flush_lsn_bytes" => "Numeric PostgreSQL confirmed flush LSN."
    }.freeze

    private

    def postgres_metric_headers
      POSTGRES_METRICS.flat_map { |name, help| ["# HELP #{name} #{help}", "# TYPE #{name} gauge"] }
    end

    def postgres_metric_lines(health)
      labels = { slot_name: health.slot_name }
      lines = postgres_presence_metric_lines(health, labels:)
      return lines unless health.present

      lines + postgres_status_metric_lines(health, labels:) + postgres_optional_metric_lines(health, labels:)
    end

    def postgres_presence_metric_lines(health, labels:)
      [
        metric_line("mammoth_postgres_slot_inspection_up", 1, labels:),
        metric_line("mammoth_postgres_slot_present", health.present ? 1 : 0, labels:)
      ]
    end

    def postgres_status_metric_lines(health, labels:)
      [
        metric_line("mammoth_postgres_slot_ready", health.ready? ? 1 : 0, labels:),
        metric_line("mammoth_postgres_slot_active", health.active ? 1 : 0, labels:),
        metric_line("mammoth_postgres_slot_wal_status", 1,
                    labels: labels.merge(wal_status: health.wal_status || "unknown")),
        metric_line("mammoth_postgres_slot_invalidated", invalidated?(health) ? 1 : 0, labels:)
      ]
    end

    def postgres_optional_metric_lines(health, labels:)
      {
        "mammoth_postgres_slot_retained_wal_bytes" => health.retained_wal_bytes,
        "mammoth_postgres_slot_safe_wal_size_bytes" => health.safe_wal_size,
        "mammoth_postgres_slot_inactive_since_timestamp_seconds" => timestamp_seconds(health.inactive_since),
        "mammoth_postgres_slot_restart_lsn_bytes" => health.restart_lsn_bytes,
        "mammoth_postgres_slot_confirmed_flush_lsn_bytes" => health.confirmed_flush_lsn_bytes
      }.filter_map { |name, value| metric_line(name, value, labels:) unless value.nil? }
    end

    def postgres_inspection_error_metric_lines
      labels = { slot_name: config.dig("replication", "slot") }
      [metric_line("mammoth_postgres_slot_inspection_up", 0, labels:)]
    end

    def timestamp_seconds(value)
      return nil if value.nil?
      return value.to_i if value.respond_to?(:to_i) && !value.is_a?(String)

      Time.parse(value.to_s).to_i
    rescue ArgumentError
      nil
    end

    def invalidated?(health)
      health.conflicting || (!health.invalidation_reason.nil? && health.invalidation_reason != "")
    end
  end
end
