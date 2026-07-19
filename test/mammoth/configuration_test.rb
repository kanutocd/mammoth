# frozen_string_literal: true

require "test_helper"

module Mammoth
  # rubocop:disable Metrics/ClassLength
  class ConfigurationTest < Minitest::Test
    def test_loads_valid_configuration
      config = Configuration.load(fixture_config_path)

      assert_equal "local_mammoth", config.dig("mammoth", "name")
      assert_equal "mammoth_prod", config.dig("replication", "slot")
      assert_equal ["mammoth_publication"], config.dig("replication", "publications")
    end

    def test_dig_returns_nil_before_load
      config = Configuration.new("unloaded.yml")

      assert_nil config.dig("mammoth", "name")
    end

    def test_raises_for_missing_configuration_file
      error = assert_raises(ConfigurationError) { Configuration.load("missing.yml") }

      assert_match(/configuration file not found/, error.message)
    end

    def test_raises_for_invalid_yaml
      with_temp_dir do |dir|
        path = write_file(File.join(dir, "bad.yml"), "mammoth: [")

        error = assert_raises(ConfigurationError) { Configuration.load(path) }

        assert_match(/invalid YAML/, error.message)
      end
    end

    def test_raises_for_non_mapping_yaml
      with_temp_dir do |dir|
        path = write_file(File.join(dir, "array.yml"), "- nope\n")

        error = assert_raises(ConfigurationError) { Configuration.load(path) }

        assert_match(/configuration must be a YAML mapping/, error.message)
      end
    end

    def test_raises_for_schema_validation_errors
      with_temp_dir do |dir|
        path = write_file(File.join(dir, "bad.yml"), minimal_config.sub("level: info", "level: tomato"))

        error = assert_raises(ConfigurationError) { Configuration.load(path) }

        assert_match(/configuration failed schema validation/, error.message)
        assert_match(/tomato/, error.message)
      end
    end

    def test_rejects_singular_publication_key
      with_temp_dir do |dir|
        path = write_file(
          File.join(dir, "singular-publication.yml"),
          minimal_config.sub("  publications:\n    - mammoth_publication", "  publication: mammoth_publication")
        )

        error = assert_raises(ConfigurationError) { Configuration.load(path) }

        assert_match(/configuration failed schema validation/, error.message)
        assert_match(/publications/, error.message)
      end
    end

    def test_accepts_optional_replication_transport_settings
      with_temp_dir do |dir|
        path = write_file(File.join(dir, "transport.yml"), minimal_config)
        config = Configuration.load(path)

        refute config.dig("replication", "auto_create_slot")
        refute config.dig("replication", "temporary_slot")
        assert_equal 10.0, config.dig("replication", "feedback_interval")
      end
    end

    def test_accepts_destinations_fanout_configuration
      with_temp_dir do |dir|
        path = write_file(File.join(dir, "fanout.yml"), fanout_config(sqlite_path: File.join(dir, "mammoth.db")))
        config = Configuration.load(path)

        assert_equal 2, config.data["destinations"].length
        assert_equal "audit_webhook", config.dig("destinations", 1, "name")
      end
    end

    def test_accepts_destination_routes_and_policy_overrides
      with_temp_dir do |dir|
        path = write_file(File.join(dir, "fanout-policy.yml"), fanout_config(sqlite_path: File.join(dir, "mammoth.db")))
        config = Configuration.load(path)
        destination = config.data.fetch("destinations").fetch(1)

        assert destination.fetch("enabled")
        assert_equal ["orders"], destination.dig("route", "tables")
        assert_equal 2, destination.dig("retry", "max_attempts")
      end
    end

    def test_accepts_destination_payload_policy
      with_temp_dir do |dir|
        replacement = <<~YAML.lines.map { |line| "  #{line}" }.join
          timeout_seconds: 5
          payload_policy:
            rules:
              - tables: [orders]
                columns: [customer_email]
                action: mask
                replacement: "[PRIVATE]"
        YAML
        yaml = minimal_config(sqlite_path: File.join(dir, "mammoth.db")).sub("  timeout_seconds: 5\n", replacement)
        config = Configuration.load(write_file(File.join(dir, "payload-policy.yml"), yaml))

        assert_equal "mask", config.dig("webhook", "payload_policy", "rules", 0, "action")
      end
    end

    def test_rejects_invalid_destination_payload_policy
      with_temp_dir do |dir|
        replacement = <<~YAML.lines.map { |line| "  #{line}" }.join
          timeout_seconds: 5
          payload_policy:
            rules:
              - columns: [customer_email]
                action: encrypt
        YAML
        yaml = minimal_config(sqlite_path: File.join(dir, "mammoth.db")).sub("  timeout_seconds: 5\n", replacement)
        path = write_file(File.join(dir, "bad-payload-policy.yml"), yaml)

        error = assert_raises(ConfigurationError) { Configuration.load(path) }

        assert_match(/configuration failed schema validation/, error.message)
        assert_match(/encrypt/, error.message)
      end
    end

    def test_accepts_node_identity_and_operational_state_adapter
      config = Configuration.load(fixture_config_path)

      assert_equal "local-mammoth-1", config.dig("node", "node_id")
      assert_equal "development", config.dig("node", "environment")
      assert_equal "sqlite", config.dig("operational_state", "adapter")
    end

    def test_rejects_unknown_destination_route_key
      with_temp_dir do |dir|
        path = write_file(
          File.join(dir, "bad-route.yml"),
          fanout_config(sqlite_path: File.join(dir, "mammoth.db")).sub("tables:", "columns:")
        )

        error = assert_raises(ConfigurationError) { Configuration.load(path) }

        assert_match(/configuration failed schema validation/, error.message)
        assert_match(/columns/, error.message)
      end
    end

    def test_rejects_duplicate_destination_names
      with_temp_dir do |dir|
        path = write_file(
          File.join(dir, "duplicate-destinations.yml"),
          fanout_config(sqlite_path: File.join(dir, "mammoth.db")).sub("audit_webhook", "primary_webhook")
        )

        error = assert_raises(ConfigurationError) { Configuration.load(path) }

        assert_match(/destination names must be unique/, error.message)
        assert_match(/primary_webhook/, error.message)
      end
    end

    def test_rejects_invalid_feedback_interval
      with_temp_dir do |dir|
        path = write_file(
          File.join(dir, "bad-feedback.yml"),
          minimal_config.sub("feedback_interval: 10.0", "feedback_interval: 0")
        )

        error = assert_raises(ConfigurationError) { Configuration.load(path) }

        assert_match(/configuration failed schema validation/, error.message)
        assert_match(/feedback_interval/, error.message)
      end
    end

    def test_raises_for_missing_schema_file
      with_temp_dir do |dir|
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config)
        schema_path = File.join(dir, "missing.schema.json")

        error = assert_raises(ConfigurationError) { Configuration.load(config_path, schema_path: schema_path) }

        assert_match(/schema file not found/, error.message)
      end
    end

    def test_raises_for_invalid_schema_json
      with_temp_dir do |dir|
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config)
        schema_path = write_file(File.join(dir, "bad.schema.json"), "{")

        error = assert_raises(ConfigurationError) { Configuration.load(config_path, schema_path: schema_path) }

        assert_match(/invalid JSON schema/, error.message)
      end
    end

    private

    def fanout_config(sqlite_path:) # rubocop:disable Metrics/MethodLength
      minimal_config(sqlite_path: sqlite_path).sub(/^webhook:.*?(?=^retry:)/m, <<~YAML)
        destinations:
          - name: primary_webhook
            type: webhook
            url: https://example.com/webhooks/postgres
            timeout_seconds: 5
          - name: audit_webhook
            type: webhook
            enabled: true
            url: https://example.com/webhooks/audit
            timeout_seconds: 5
            route:
              schemas:
                - public
              tables:
                - orders
              operations:
                - insert
                - update
            retry:
              max_attempts: 2
              schedule_seconds:
                - 1
                - 3

      YAML
    end
  end
  # rubocop:enable Metrics/ClassLength
end
