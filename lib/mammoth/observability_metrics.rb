# frozen_string_literal: true

module Mammoth
  # Prometheus formatting helpers for operational and dispatch metrics.
  module ObservabilityMetrics
    # Maps canonical CDC core metric names to Mammoth's Prometheus counters.
    DISPATCH_METRIC_NAMES = {
      CDC::Core::Observer.started_metric_name => "mammoth_dispatch_started_total",
      CDC::Core::Observer.succeeded_metric_name => "mammoth_dispatch_succeeded_total",
      CDC::Core::Observer.failed_metric_name => "mammoth_dispatch_failed_total",
      CDC::Core::Observer.skipped_metric_name => "mammoth_dispatch_skipped_total"
    }.freeze

    private

    def metric_headers
      operational_metric_headers + dispatch_metric_headers
    end

    def operational_metric_headers
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

    def dispatch_metric_headers
      [
        "# HELP mammoth_dispatch_started_total Number of CDC work items submitted for delivery.",
        "# TYPE mammoth_dispatch_started_total counter",
        "# HELP mammoth_dispatch_succeeded_total Number of successful CDC delivery results.",
        "# TYPE mammoth_dispatch_succeeded_total counter",
        "# HELP mammoth_dispatch_failed_total Number of failed CDC delivery results.",
        "# TYPE mammoth_dispatch_failed_total counter",
        "# HELP mammoth_dispatch_skipped_total Number of skipped CDC delivery results.",
        "# TYPE mammoth_dispatch_skipped_total counter"
      ]
    end

    def dispatch_metric_lines
      dispatch_metrics.snapshot.sort_by { |entry| [entry.fetch(:name), entry.fetch(:tags).to_a] }.filter_map do |entry|
        name = DISPATCH_METRIC_NAMES[entry.fetch(:name)]
        metric_line(name, entry.fetch(:value), labels: entry.fetch(:tags)) if name
      end
    end

    def metric_line(name, value, destination: nil, labels: {})
      labels = { "mammoth_name" => mammoth_name }.merge(labels.transform_keys(&:to_s))
      labels["destination"] = destination if destination
      %(#{name}{#{labels.map { |label, label_value| %(#{label}="#{escape_label(label_value)}") }.join(",")}} #{Integer(value)})
    end

    def escape_label(value)
      value.to_s.gsub("\\", "\\\\").gsub('"', '\\"').gsub("\n", "\\n")
    end
  end
end
