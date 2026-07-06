# frozen_string_literal: true

require "test_helper"

module Mammoth
  class ConfigurationProvidersTest < Minitest::Test
    def test_file_provider_loads_yaml_configuration
      provider = Configuration::Providers::FileProvider.new(fixture_config_path)

      config = provider.load

      assert_instance_of Configuration, config
      assert_equal fixture_config_path, config.path
    end

    def test_hash_provider_loads_hash_configuration
      data = YAML.safe_load(minimal_config(sqlite_path: "data/provider.db"), aliases: false)

      config = Configuration::Providers::HashProvider.new(data, path: "memory").load

      assert_instance_of Configuration, config
      assert_equal "memory", config.path
      assert_equal "data/provider.db", config.dig("sqlite", "path")
    end

    def test_hash_provider_defaults_path
      data = YAML.safe_load(minimal_config, aliases: false)

      config = Configuration.from_hash(data)

      assert_equal "<hash>", config.path
    end

    def test_hash_provider_defensively_copies_data
      data = YAML.safe_load(minimal_config(sqlite_path: "data/original.db"), aliases: false)

      config = Configuration.from_hash(data)
      data.fetch("sqlite")["path"] = "data/mutated.db"

      assert_equal "data/original.db", config.dig("sqlite", "path")
    end

    def test_hash_provider_rejects_non_mapping
      error = assert_raises(ConfigurationError) { Configuration.from_hash([]) }

      assert_match(/configuration must be a YAML mapping/, error.message)
    end
  end
end
