# frozen_string_literal: true

require "json"
require "securerandom"
require "time"

module Mammoth
  # Serializes CDC transaction envelopes into webhook payloads.
  #
  # Mammoth uses transaction envelopes as the safest delivery and checkpointing
  # boundary for concurrent delivery. A transaction payload preserves the commit
  # position and groups the row-level changes that belong to the same database
  # transaction.
  class TransactionEnvelopeSerializer
    # Default payload type for transaction webhook delivery.
    PAYLOAD_TYPE = "transaction.committed"

    # Serialize a CDC::Core::TransactionEnvelope into a Hash.
    #
    # @param envelope [CDC::Core::TransactionEnvelope] transaction envelope
    # @return [Hash] webhook-ready transaction payload
    def self.call(envelope)
      new(envelope).call
    end

    # @param envelope [CDC::Core::TransactionEnvelope] transaction envelope
    def initialize(envelope)
      unless envelope.is_a?(CDC::Core::TransactionEnvelope)
        raise ArgumentError, "envelope must be a CDC::Core::TransactionEnvelope"
      end

      @envelope = envelope
    end

    # Return the webhook payload.
    #
    # @return [Hash] transaction webhook payload
    def call
      event_payloads = envelope.events.map { |event| EventSerializer.call(event) }
      {
        "event_id" => envelope_metadata["event_id"] || SecureRandom.uuid,
        "type" => PAYLOAD_TYPE,
        "source" => first_event_value(event_payloads, "source") || EventSerializer::DEFAULT_SOURCE,
        "transaction_id" => envelope.transaction_id,
        "source_position" => source_position(event_payloads),
        "commit_lsn" => source_position(event_payloads),
        "committed_at" => committed_at,
        "event_count" => event_payloads.length,
        "events" => event_payloads,
        "metadata" => envelope_metadata
      }
    end

    # Return JSON representation of the transaction payload.
    #
    # @return [String] JSON representation
    def to_json(*_args)
      JSON.generate(call)
    end

    private

    attr_reader :envelope

    def stringify_keys(hash)
      hash.to_h.transform_keys(&:to_s)
    end

    def envelope_metadata
      @envelope_metadata ||= stringify_keys(envelope.metadata)
    end

    def source_position(event_payloads)
      envelope.commit_lsn ||
        first_event_value(event_payloads.reverse, "source_position")
    end

    def committed_at
      value = envelope.committed_at
      return value.iso8601 if value.respond_to?(:iso8601)

      value || Time.now.utc.iso8601
    end

    def first_event_value(event_payloads, key)
      event_payloads.find { |payload| payload[key] }&.fetch(key)
    end
  end
end
