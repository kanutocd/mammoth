# frozen_string_literal: true

require "digest"
require "json"

module Mammoth
  # Applies deterministic destination-scoped projection and redaction rules.
  #
  # Policies operate on serialized Mammoth payloads, never on CDC-core work
  # items. Column rules scrub every canonical row-value representation: data,
  # identity, and old/new values in changes.
  class PayloadPolicy
    DEFAULT_MASK = "[REDACTED]"
    POLICY_METADATA_KEY = "mammoth_payload_policy"
    SUPPORTED_ACTIONS = %w[remove mask].freeze

    attr_reader :config, :fingerprint

    # @param config [Hash, nil] validated payload-policy configuration
    def initialize(config = nil)
      @config = deep_freeze(stringify_keys(config || {}))
      validate!
      @fingerprint = build_fingerprint if active?
    end

    # @return [Boolean] whether the policy contains transformation rules
    def active?
      rules.any?
    end

    # Transform one canonical event or transaction payload.
    #
    # @param payload [Hash] canonical serialized Mammoth payload
    # @return [Hash] independent JSON-compatible destination payload
    def apply(payload)
      return payload unless active?

      transformed = JSON.parse(JSON.generate(payload))
      events_for(transformed).each { |event| apply_rules(event) }
      metadata = transformed["metadata"]
      metadata = {} unless metadata.is_a?(Hash) # steep:ignore
      transformed["metadata"] = metadata
      metadata[POLICY_METADATA_KEY] = { "fingerprint" => fingerprint }
      transformed
    end

    private

    def rules
      config.fetch("rules", [])
    end

    def validate!
      rules.each_with_index do |rule, index|
        action = rule["action"].to_s
        unless SUPPORTED_ACTIONS.include?(action)
          raise ConfigurationError, "payload policy rule #{index} has unsupported action #{action}"
        end
        raise ConfigurationError, "payload policy rule #{index} requires columns" if Array(rule["columns"]).empty?
      end
    end

    def events_for(payload)
      return payload.fetch("events") if payload["type"] == TransactionEnvelopeSerializer::PAYLOAD_TYPE

      [payload]
    end

    def apply_rules(event)
      rules.each do |rule|
        apply_rule(event, rule) if match?(event, rule)
      end
    end

    def apply_rule(event, rule)
      columns = rule.fetch("columns")
      if rule.fetch("action") == "remove"
        remove_columns(event, columns)
      else
        mask_columns(event, columns, rule.fetch("replacement", DEFAULT_MASK))
      end
    end

    def remove_columns(event, columns)
      %w[data identity].each do |field|
        columns.each { |column| event[field]&.delete(column) }
      end
      changes = Array(event["changes"]) # : Array[untyped]
      event["changes"] = changes.reject { |change| columns.include?(change["name"]) }
    end

    def mask_columns(event, columns, replacement)
      %w[data identity].each do |field|
        columns.each { |column| mask_map_value(event[field], column, replacement) }
      end
      changes = Array(event["changes"]) # : Array[untyped]
      changes.each do |change|
        next unless columns.include?(change["name"])

        %w[old_value new_value].each do |value_key|
          change[value_key] = replacement if change.key?(value_key) && !change[value_key].nil?
        end
      end
    end

    def mask_map_value(map, column, replacement)
      return unless map.is_a?(Hash) && map.key?(column)
      return if map[column].nil?

      map[column] = replacement
    end

    def match?(event, rule)
      matches?(rule["schemas"], event["namespace"]) &&
        matches?(rule["tables"], event["entity"]) &&
        matches?(rule["operations"], event["operation"])
    end

    def matches?(configured, actual)
      values = Array(configured) # : Array[untyped]
      values.empty? || values.any? { |value| value.to_s.casecmp?(actual.to_s) }
    end

    def build_fingerprint
      canonical = canonicalize(config)
      "sha256:#{Digest::SHA256.hexdigest(JSON.generate(canonical))}"
    end

    def canonicalize(value)
      return value.map { |item| canonicalize(item) } if value.is_a?(Array)
      return value unless value.is_a?(Hash)

      value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
    end

    def stringify_keys(value)
      return value.map { |item| stringify_keys(item) } if value.is_a?(Array)
      return value unless value.is_a?(Hash)

      value.to_h { |key, item| [key.to_s, stringify_keys(item)] }
    end

    def deep_freeze(value)
      value.each_value { |item| deep_freeze(item) } if value.is_a?(Hash)
      value.each { |item| deep_freeze(item) } if value.is_a?(Array)
      value.freeze
    end
  end
end
