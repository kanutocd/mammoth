# frozen_string_literal: true

require "test_helper"

module Mammoth
  class PayloadPolicyTest < Minitest::Test
    def test_inactive_policy_preserves_canonical_payload_object
      payload = event_payload
      policy = PayloadPolicy.new

      assert_same payload, policy.apply(payload)
      refute policy.active?
      assert_nil policy.fingerprint
    end

    def test_remove_scrubs_data_identity_and_changes_without_mutating_canonical_payload # rubocop:disable Metrics/MethodLength
      payload = event_payload
      policy = PayloadPolicy.new(
        rules: [
          {
            schemas: ["PUBLIC"],
            tables: ["ORDERS"],
            operations: ["UPDATE"],
            columns: %w[email account_id],
            action: "remove"
          }
        ]
      )

      transformed = policy.apply(payload)

      assert_equal({ "id" => 7 }, transformed.fetch("data"))
      assert_equal({ "id" => 7 }, transformed.fetch("identity"))
      assert_equal ["status"], transformed.fetch("changes").map { |change| change.fetch("name") } # rubocop:disable Lint/AmbiguousBlockAssociation
      assert_equal "private@example.com", payload.dig("data", "email")
      assert_match(/\Asha256:[0-9a-f]{64}\z/, policy.fingerprint)
      assert_equal(
        policy.fingerprint,
        transformed.dig("metadata", PayloadPolicy::POLICY_METADATA_KEY, "fingerprint")
      )
    end

    def test_mask_uses_default_and_explicit_replacements_while_preserving_nulls # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      policy = PayloadPolicy.new(
        "rules" => [
          { "columns" => ["email"], "action" => "mask" },
          {
            "tables" => ["orders"],
            "columns" => ["account_id"],
            "action" => "mask",
            "replacement" => "[PRIVATE]"
          },
          { "columns" => ["nullable_secret"], "action" => "mask" }
        ]
      )

      payload = event_payload
      payload.fetch("data")["nullable_secret"] = nil
      transformed = policy.apply(payload)
      changes = transformed.fetch("changes").to_h { |change| [change.fetch("name"), change] }

      assert_equal PayloadPolicy::DEFAULT_MASK, transformed.dig("data", "email")
      assert_equal "[PRIVATE]", transformed.dig("identity", "account_id")
      assert_nil changes.fetch("email").fetch("old_value")
      assert_equal PayloadPolicy::DEFAULT_MASK, changes.fetch("email").fetch("new_value")
      assert_equal "[PRIVATE]", changes.fetch("account_id").fetch("old_value")
      assert_equal "[PRIVATE]", changes.fetch("account_id").fetch("new_value")
      assert_nil transformed.dig("data", "nullable_secret")
      assert policy.config.frozen?
    end

    def test_remove_accepts_missing_optional_row_maps
      payload = event_payload.merge("data" => nil, "identity" => nil)
      policy = PayloadPolicy.new("rules" => [{ "columns" => ["email"], "action" => "remove" }])

      transformed = policy.apply(payload)

      assert_nil transformed["data"]
      assert_nil transformed["identity"]
    end

    def test_policy_replaces_missing_metadata_map_with_policy_evidence
      payload = event_payload.merge("metadata" => nil)
      policy = PayloadPolicy.new("rules" => [{ "columns" => ["email"], "action" => "remove" }])

      transformed = policy.apply(payload)

      assert_equal policy.fingerprint,
                   transformed.dig("metadata", PayloadPolicy::POLICY_METADATA_KEY, "fingerprint")
    end

    def test_transaction_policy_transforms_only_matching_child_events # rubocop:disable Metrics/MethodLength
      payload = {
        "type" => TransactionEnvelopeSerializer::PAYLOAD_TYPE,
        "event_id" => "tx-1",
        "transaction_id" => 1,
        "source_position" => "0/2",
        "events" => [
          event_payload,
          event_payload.merge("entity" => "audit_log", "data" => { "email" => "retained@example.com" })
        ],
        "metadata" => {}
      }
      policy = PayloadPolicy.new(
        "rules" => [
          {
            "tables" => ["orders"],
            "columns" => ["email"],
            "action" => "remove"
          }
        ]
      )

      transformed = policy.apply(payload)

      refute transformed.fetch("events").fetch(0).fetch("data").key?("email")
      assert_equal "retained@example.com", transformed.fetch("events").fetch(1).dig("data", "email")
      assert_equal policy.fingerprint,
                   transformed.dig("metadata", PayloadPolicy::POLICY_METADATA_KEY, "fingerprint")
    end

    def test_fingerprint_is_stable_across_hash_key_order
      first = PayloadPolicy.new("rules" => [{ "columns" => ["email"], "action" => "remove" }])
      second = PayloadPolicy.new("rules" => [{ "action" => "remove", "columns" => ["email"] }])

      assert_equal first.fingerprint, second.fingerprint
    end

    def test_rejects_unsupported_action
      error = assert_raises(ConfigurationError) do
        PayloadPolicy.new("rules" => [{ "columns" => ["email"], "action" => "encrypt" }])
      end

      assert_match(/unsupported action encrypt/, error.message)
    end

    def test_rejects_rule_without_columns
      error = assert_raises(ConfigurationError) do
        PayloadPolicy.new("rules" => [{ "columns" => [], "action" => "remove" }])
      end

      assert_match(/requires columns/, error.message)
    end

    private

    def event_payload
      {
        "event_id" => "event-1",
        "source" => "postgresql",
        "operation" => "update",
        "namespace" => "public",
        "entity" => "orders",
        "identity" => { "id" => 7, "account_id" => "acct-secret" },
        "source_position" => "0/1",
        "data" => {
          "id" => 7,
          "email" => "private@example.com",
          "account_id" => "acct-secret"
        },
        "changes" => [
          { "name" => "email", "old_value" => nil, "new_value" => "private@example.com" },
          { "name" => "account_id", "old_value" => "old-secret", "new_value" => "acct-secret" },
          { "name" => "status", "old_value" => "pending", "new_value" => "paid" }
        ],
        "metadata" => {}
      }
    end
  end
end
