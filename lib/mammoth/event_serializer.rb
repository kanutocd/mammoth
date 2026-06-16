# frozen_string_literal: true

require "json"
require "securerandom"
require "time"

module Mammoth
  # Serializes CDC-core change events into webhook payloads.
  #
  # The serializer projects Mammoth's sink payload from CDC vocabulary rather
  # than pgoutput protocol vocabulary. That keeps webhook delivery independent
  # from PostgreSQL-specific message shapes while preserving source metadata such
  # as commit LSN and transaction identity when available.
  class EventSerializer
    DEFAULT_SOURCE = "postgresql"

    # Serialize an event-like object into a webhook-ready Hash.
    #
    # @param event [Hash, #to_h] normalized CDC event
    # @return [Hash] webhook payload
    def self.call(event)
      new(event).call
    end

    # @param event [Hash, #to_h] normalized CDC event
    def initialize(event)
      @event = event.respond_to?(:to_h) ? event.to_h : event
    end

    # Return the webhook payload.
    #
    # @return [Hash] webhook payload
    def call
      event_hash = stringify_keys(@event)
      {
        "event_id" => event_hash["event_id"] || SecureRandom.uuid,
        "source" => event_hash["source"] || DEFAULT_SOURCE,
        "operation" => normalize_operation(event_hash.fetch("operation")),
        "namespace" => event_hash["namespace"] || event_hash["schema"],
        "entity" => event_hash["entity"] || event_hash["table"],
        "identity" => event_hash["identity"] || event_hash["primary_key"],
        "source_position" => event_hash["source_position"] || event_hash["commit_lsn"],
        "transaction_id" => event_hash["transaction_id"],
        "occurred_at" => occurred_at(event_hash),
        "data" => event_data(event_hash),
        "changes" => event_hash["changes"] || [],
        "metadata" => event_hash["metadata"] || {}
      }
    end

    # Return JSON representation of the webhook payload.
    #
    # @return [String] JSON representation of the payload
    def to_json(*_args)
      JSON.generate(call)
    end

    private

    def stringify_keys(hash)
      hash.to_h.transform_keys(&:to_s)
    end

    def normalize_operation(operation)
      operation.to_s
    end

    def occurred_at(event_hash)
      value = event_hash["occurred_at"]
      return value.iso8601 if value.respond_to?(:iso8601)

      value || Time.now.utc.iso8601
    end

    def event_data(event_hash)
      event_hash["data"] || event_hash["new_values"] || event_hash["old_values"] || {}
    end
  end
end
