# frozen_string_literal: true

module Mammoth
  # Immutable delivery boundary containing canonical identity and outbound data.
  PreparedDelivery = Data.define(:canonical_payload, :payload, :policy_fingerprint) do
    # Serialize and apply one destination payload policy.
    #
    # @param work [CDC::Core::ChangeEvent, CDC::Core::TransactionEnvelope]
    # @param serializer [#call] canonical Mammoth serializer
    # @param payload_policy [Mammoth::PayloadPolicy]
    # @return [Mammoth::PreparedDelivery]
    def self.build(work, serializer:, payload_policy:)
      canonical_payload = serializer.call(work)
      new(
        canonical_payload: canonical_payload,
        payload: payload_policy.apply(canonical_payload),
        policy_fingerprint: payload_policy.fingerprint
      )
    end

    # Reconstruct a prepared delivery from a persisted destination payload.
    #
    # @param payload [Hash] previously prepared destination payload
    # @return [Mammoth::PreparedDelivery]
    def self.from_payload(payload)
      fingerprint = payload.dig("metadata", PayloadPolicy::POLICY_METADATA_KEY, "fingerprint")
      new(canonical_payload: payload, payload: payload, policy_fingerprint: fingerprint)
    end
  end
end
