# frozen_string_literal: true

require_relative "mammoth/version"
require_relative "mammoth/errors"
require_relative "mammoth/configuration"
require_relative "mammoth/status"
require_relative "mammoth/sqlite_store"
require_relative "mammoth/checkpoint_store"
require_relative "mammoth/dead_letter_store"
require_relative "mammoth/event_serializer"
require_relative "mammoth/webhook_sink"
require_relative "mammoth/delivery_worker"
require_relative "mammoth/sources/postgres"
require_relative "mammoth/cdc_source"
require_relative "mammoth/replication_consumer"
require_relative "mammoth/application"
require_relative "mammoth/cli"

# Mammoth is a self-hosted PostgreSQL event relay.
#
# Mammoth v0.1.0 focuses on a deliberately small, boring product slice:
# PostgreSQL change events are normalized, persisted through local operational
# state, and delivered to webhook destinations.
module Mammoth
end
