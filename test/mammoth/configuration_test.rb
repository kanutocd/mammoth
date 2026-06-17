# frozen_string_literal: true

require "test_helper"

module Mammoth
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
  end
end
