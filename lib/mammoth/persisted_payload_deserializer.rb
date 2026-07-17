# frozen_string_literal: true

require "time"

module Mammoth
  # Reconstructs exact CDC core work items from persisted webhook payloads.
  #
  # Dead letters and sample files contain Mammoth's JSON delivery projection,
  # not live CDC objects. This class is the explicit boundary that converts
  # those persisted representations back into core vocabulary.
  class PersistedPayloadDeserializer
    class << self
      # Deserialize one persisted event payload.
      #
      # @param payload [Hash] Mammoth event payload
      # @return [CDC::Core::ChangeEvent] reconstructed core event
      def event(payload)
        attributes = stringify_keys(payload)
        data = attributes["data"]
        metadata = enriched_metadata(attributes)

        CDC::Core::ChangeEvent.new(
          operation: attributes.fetch("operation"),
          schema: attributes["namespace"] || attributes.fetch("schema"),
          table: attributes["entity"] || attributes.fetch("table"),
          old_values: attributes["old_values"] || delete_values(attributes, data),
          new_values: attributes["new_values"] || changed_values(attributes, data),
          primary_key: attributes["identity"] || attributes["primary_key"],
          transaction_id: attributes["transaction_id"],
          commit_lsn: attributes["commit_lsn"] || attributes["source_position"],
          sequence_number: attributes["sequence_number"],
          occurred_at: parse_time(attributes["occurred_at"]),
          metadata: metadata
        )
      rescue KeyError, ArgumentError, TypeError => e
        raise ConfigurationError, "invalid persisted CDC event: #{e.message}"
      end

      # Deserialize one persisted transaction payload.
      #
      # @param payload [Hash] Mammoth transaction webhook payload
      # @return [CDC::Core::TransactionEnvelope] reconstructed core transaction
      def transaction(payload)
        attributes = stringify_keys(payload)
        CDC::Core::TransactionEnvelope.new(
          transaction_id: attributes.fetch("transaction_id"),
          events: attributes.fetch("events").map { |event_payload| event(event_payload) },
          commit_lsn: attributes["commit_lsn"] || attributes["source_position"],
          committed_at: parse_time(attributes["committed_at"]),
          metadata: enriched_metadata(attributes)
        )
      rescue KeyError, ArgumentError, TypeError => e
        raise ConfigurationError, "invalid persisted CDC transaction: #{e.message}"
      end

      private

      def stringify_keys(payload)
        payload.to_h.transform_keys(&:to_s)
      end

      def enriched_metadata(attributes)
        metadata = stringify_keys(attributes["metadata"] || {})
        %w[event_id source source_position changes type].each do |key|
          metadata[key] = attributes[key] if attributes.key?(key)
        end
        metadata
      end

      def delete_values(attributes, data)
        data if attributes["operation"].to_s == "delete"
      end

      def changed_values(attributes, data)
        data unless attributes["operation"].to_s == "delete"
      end

      def parse_time(value)
        return value if value.nil? || value.is_a?(Time)

        Time.iso8601(value.to_s)
      end
    end
  end
end
