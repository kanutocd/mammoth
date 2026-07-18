# frozen_string_literal: true

require "json"
require "digest"
require "time"

module Mammoth
  # Serializes CDC-core change events into webhook payloads.
  #
  # The serializer projects Mammoth's sink payload from CDC vocabulary rather
  # than pgoutput protocol vocabulary. That keeps webhook delivery independent
  # from PostgreSQL-specific message shapes while preserving source metadata such
  # as commit LSN and transaction identity when available.
  class EventSerializer
    # Default source label used in serialized webhook payloads.
    DEFAULT_SOURCE = "postgresql"

    # Serialize a core change event into a webhook-ready Hash.
    #
    # @param event [CDC::Core::ChangeEvent] normalized CDC event
    # @return [Hash] webhook payload
    def self.call(event)
      new(event).call
    end

    # @param event [CDC::Core::ChangeEvent] normalized CDC event
    def initialize(event)
      raise ArgumentError, "event must be a CDC::Core::ChangeEvent" unless event.is_a?(CDC::Core::ChangeEvent)

      @event = event
    end

    # Return the webhook payload.
    #
    # @return [Hash] webhook payload
    def call
      event_hash = stringify_keys(@event.to_h)
      metadata = stringify_keys(event_hash["metadata"] || {})
      {
        "event_id" => event_id(event_hash, metadata),
        "source" => source(metadata),
        "operation" => normalize_operation(event_hash.fetch("operation")),
        "namespace" => event_hash["schema"],
        "entity" => event_hash["table"],
        "identity" => event_hash["primary_key"],
        "source_position" => event_hash["commit_lsn"],
        "transaction_id" => event_hash["transaction_id"],
        "occurred_at" => occurred_at(event_hash),
        "data" => event_data(event_hash),
        "changes" => serialized_changes(event_hash, metadata),
        "metadata" => metadata
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

    def event_id(event_hash, metadata)
      metadata["event_id"] || deterministic_event_id(event_hash, metadata)
    end

    def deterministic_event_id(event_hash, metadata)
      identity = {
        source: source(metadata),
        transaction_id: event_hash["transaction_id"],
        source_position: event_hash["commit_lsn"],
        namespace: event_hash["schema"],
        entity: event_hash["table"],
        operation: normalize_operation(event_hash.fetch("operation")),
        primary_key: event_hash["primary_key"],
        data: event_data(event_hash)
      }
      "evt_#{Digest::SHA256.hexdigest(JSON.generate(identity))}"
    end

    def source(metadata)
      metadata["source"] || DEFAULT_SOURCE
    end

    def occurred_at(event_hash)
      value = event_hash["occurred_at"]
      return value.iso8601 if value.respond_to?(:iso8601)

      value || Time.now.utc.iso8601
    end

    def event_data(event_hash)
      event_hash["data"] || event_hash["new_values"] || event_hash["old_values"] || {}
    end

    def serialized_changes(event_hash, metadata)
      return metadata["changes"] if metadata.key?("changes")
      return [] unless changes_available?(event_hash)

      @event.changes.map(&:to_h)
    end

    def changes_available?(event_hash)
      return true unless normalize_operation(event_hash.fetch("operation")) == "update"

      old_values = event_hash["old_values"]
      new_values = event_hash["new_values"]
      old_values.is_a?(Hash) && new_values.is_a?(Hash) && old_values.keys.sort == new_values.keys.sort
    end
  end
end
