# frozen_string_literal: true

require "json"
require "json-schema"
require "yaml"

module Mammoth
  # Loads and validates Mammoth configuration.
  #
  # Configuration is intentionally schema-backed so the same contract can power
  # editor IntelliSense, preflight validation, and runtime startup checks.
  class Configuration
    # Default JSON Schema used to validate Mammoth YAML configuration files.
    DEFAULT_SCHEMA_PATH = File.expand_path("../../config/mammoth.schema.json", __dir__.to_s)

    attr_reader :path, :data, :schema_path

    # Load and validate a configuration file.
    #
    # @param path [String] YAML configuration path
    # @param schema_path [String] JSON Schema path
    # @return [Mammoth::Configuration] loaded configuration
    # @raise [Mammoth::ConfigurationError] when the file is missing or invalid
    def self.load(path, schema_path: DEFAULT_SCHEMA_PATH)
      Providers::FileProvider.new(path).load(schema_path: schema_path)
    end

    # Build and validate a configuration from an in-memory Hash.
    #
    # @param data [Hash] configuration data
    # @param path [String, nil] optional display path/source
    # @param schema_path [String] JSON Schema path
    # @return [Mammoth::Configuration] loaded configuration
    # @raise [Mammoth::ConfigurationError] when the data is invalid
    def self.from_hash(data, path: nil, schema_path: DEFAULT_SCHEMA_PATH)
      Providers::HashProvider.new(data, path: path).load(schema_path: schema_path)
    end

    # @param path [String] YAML configuration path
    # @param schema_path [String] JSON Schema path
    # @param data [Hash, nil] already parsed configuration data
    def initialize(path, schema_path: DEFAULT_SCHEMA_PATH, data: nil)
      @path = path
      @schema_path = schema_path
      @data = data
    end

    # Load and validate the configuration file.
    #
    # @return [Mammoth::Configuration] self
    # @raise [Mammoth::ConfigurationError] when validation fails
    def load
      @data ||= load_yaml_file
      raise ConfigurationError, "configuration must be a YAML mapping" unless data.is_a?(Hash)

      validate_schema!
      validate_destination_names!
      self
    rescue Psych::SyntaxError => e
      raise ConfigurationError, "invalid YAML in #{path}: #{e.message}"
    end

    # Fetch a nested value from the loaded configuration.
    #
    # @param keys [Array<String>] nested hash keys
    # @return [Object, nil] value or nil
    def dig(*keys)
      data&.dig(*keys)
    end

    private

    def load_yaml_file
      raise ConfigurationError, "configuration file not found: #{path}" unless path && File.file?(path)

      YAML.safe_load_file(path, permitted_classes: [], aliases: false)
    end

    def validate_schema!
      raise ConfigurationError, "schema file not found: #{schema_path}" unless File.file?(schema_path)

      schema = JSON.parse(File.read(schema_path))
      JSON::Validator.fully_validate(schema, data, validate_schema: false).tap do |errors|
        raise ConfigurationError, schema_error_message(errors) unless errors.empty?
      end
    rescue JSON::ParserError => e
      raise ConfigurationError, "invalid JSON schema in #{schema_path}: #{e.message}"
    end

    def schema_error_message(errors)
      (["configuration failed schema validation:"] + errors.map { |error| "- #{error}" }).join("\n")
    end

    def validate_destination_names!
      destinations = data["destinations"]
      return unless destinations

      names = destinations.map { |destination| destination["name"] }
      duplicates = names.tally.select { |_name, count| count > 1 }.keys
      return if duplicates.empty?

      raise ConfigurationError, "destination names must be unique: #{duplicates.join(", ")}"
    end

    # Configuration provider contracts shared by CLI and future control agents.
    module Providers
      # Loads configuration from a YAML file.
      class FileProvider
        attr_reader :path

        # @param path [String] YAML configuration path
        def initialize(path)
          @path = path
        end

        # @param schema_path [String] JSON Schema path
        # @return [Mammoth::Configuration]
        def load(schema_path: Configuration::DEFAULT_SCHEMA_PATH)
          Configuration.new(path, schema_path: schema_path).load
        end
      end

      # Loads configuration from an already parsed Hash.
      class HashProvider
        attr_reader :data, :path

        # @param data [Hash] configuration data
        # @param path [String, nil] optional source name for diagnostics/status
        def initialize(data, path: nil)
          @data = data
          @path = path || "<hash>"
        end

        # @param schema_path [String] JSON Schema path
        # @return [Mammoth::Configuration]
        def load(schema_path: Configuration::DEFAULT_SCHEMA_PATH)
          Configuration.new(path, schema_path: schema_path, data: deep_copy(data)).load
        end

        private

        def deep_copy(value)
          Marshal.load(Marshal.dump(value))
        end
      end
    end
  end
end
