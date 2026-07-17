# frozen_string_literal: true

require "cdc/core"

require_relative "mammoth/version"
require_relative "mammoth/errors"
require_relative "mammoth/registry"
require_relative "mammoth/configuration"
require_relative "mammoth/lifecycle_hooks"
require_relative "mammoth/node_identity"
require_relative "mammoth/capabilities"
require_relative "mammoth/status"
require_relative "mammoth/commands/validate_command"
require_relative "mammoth/commands/bootstrap_command"
require_relative "mammoth/commands/status_command"
require_relative "mammoth/commands/start_command"
require_relative "mammoth/commands/deliver_sample_command"
require_relative "mammoth/commands/dead_letters_command"
require_relative "mammoth/dispatch_metrics"
require_relative "mammoth/metrics_observer"
require_relative "mammoth/observability_metrics"
require_relative "mammoth/observability_snapshot"
require_relative "mammoth/observability_server"
require_relative "mammoth/sqlite_store"
require_relative "mammoth/checkpoint_store"
require_relative "mammoth/dead_letter_store"
require_relative "mammoth/delivered_envelope_store"
require_relative "mammoth/event_serializer"
require_relative "mammoth/transaction_envelope_serializer"
require_relative "mammoth/route_filter"
require_relative "mammoth/webhook_sink"
require_relative "mammoth/operational_state/adapter"
require_relative "mammoth/operational_state/sqlite_adapter"
require_relative "mammoth/operational_state/registry"
require_relative "mammoth/destinations/adapter"
require_relative "mammoth/destinations/webhook_adapter"
require_relative "mammoth/destinations/registry"
require_relative "mammoth/delivery_worker"
require_relative "mammoth/fanout_delivery_worker"
require_relative "mammoth/delivery_processor"
require_relative "mammoth/concurrent_delivery_runtime"
require_relative "mammoth/runtimes/adapter"
require_relative "mammoth/runtimes/inline_adapter"
require_relative "mammoth/runtimes/concurrent_adapter"
require_relative "mammoth/runtimes/registry"
require_relative "mammoth/sources/postgres"
require_relative "mammoth/cdc_source"
require_relative "mammoth/replication_consumer"
require_relative "mammoth/application"
require_relative "mammoth/dead_letter_commands"
require_relative "mammoth/cli"

# Mammoth is a self-hosted PostgreSQL event relay.
#
# Mammoth 0.8.x is a single-node PostgreSQL CDC relay with webhook fanout,
# replayable operational SQLite state, health/metrics endpoints, and explicit
# extension contracts for state, destination, runtime, lifecycle, configuration,
# and local command integrations.
module Mammoth
  OperationalState::Registry.register("sqlite", OperationalState::SQLiteAdapter)
  Destinations::Registry.register("webhook", Destinations::WebhookAdapter)
  Runtimes::Registry.register("inline", Runtimes::InlineAdapter)
  Runtimes::Registry.register("concurrent", Runtimes::ConcurrentAdapter)
end
