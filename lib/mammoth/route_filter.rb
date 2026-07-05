# frozen_string_literal: true

module Mammoth
  # Matches CDC events and transaction envelopes against destination route rules.
  class RouteFilter
    attr_reader :schemas, :tables, :operations

    def initialize(config = nil)
      route = config || {}
      @schemas = normalized_set(route["schemas"])
      @tables = normalized_set(route["tables"])
      @operations = normalized_set(route["operations"])
    end

    def match?(work, serializer:)
      match_payload?(serializer.call(work))
    end

    def match_payload?(payload)
      if transaction_payload?(payload)
        payload.fetch("events").any? { |event| event_match?(event) }
      else
        event_match?(payload)
      end
    end

    private

    def normalized_set(values)
      return [] unless values

      values.map { |value| value.to_s.downcase }.freeze
    end

    def transaction_payload?(payload)
      payload.fetch("type", nil) == TransactionEnvelopeSerializer::PAYLOAD_TYPE
    end

    def event_match?(payload)
      matches?(schemas, payload["namespace"]) &&
        matches?(tables, payload["entity"]) &&
        matches?(operations, payload["operation"])
    end

    def matches?(allowed_values, actual_value)
      allowed_values.empty? || allowed_values.include?(actual_value.to_s.downcase)
    end
  end
end
