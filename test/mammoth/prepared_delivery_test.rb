# frozen_string_literal: true

require "test_helper"

module Mammoth
  class PreparedDeliveryTest < Minitest::Test
    def test_build_keeps_canonical_identity_and_applies_policy
      event = core_event(data: { "id" => 1, "email" => "private@example.com" })
      policy = PayloadPolicy.new("rules" => [{ "columns" => ["email"], "action" => "remove" }])

      prepared = PreparedDelivery.build(event, serializer: EventSerializer, payload_policy: policy)

      assert_equal "private@example.com", prepared.canonical_payload.dig("data", "email")
      refute prepared.payload.fetch("data").key?("email")
      assert_equal policy.fingerprint, prepared.policy_fingerprint
    end

    def test_from_payload_preserves_exact_payload_and_fingerprint
      payload = {
        "event_id" => "event-1",
        "metadata" => {
          PayloadPolicy::POLICY_METADATA_KEY => { "fingerprint" => "sha256:abc" }
        }
      }

      prepared = PreparedDelivery.from_payload(payload)

      assert_same payload, prepared.payload
      assert_same payload, prepared.canonical_payload
      assert_equal "sha256:abc", prepared.policy_fingerprint
    end

    def test_from_payload_accepts_legacy_payload_without_fingerprint
      prepared = PreparedDelivery.from_payload("event_id" => "event-1")

      assert_nil prepared.policy_fingerprint
    end
  end
end
