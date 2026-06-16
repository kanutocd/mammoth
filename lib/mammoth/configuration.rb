# frozen_string_literal: true

require "json"
require "json-schema"
require "yaml"

module Mammoth
  # Loads and validates Mammoth YAML configuration.
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
      new(path, schema_path: schema_path).load
    end

    # @param path [String] YAML configuration path
    # @param schema_path [String] JSON Schema path
    def initialize(path, schema_path: DEFAULT_SCHEMA_PATH)
      @path = path
      @schema_path = schema_path
      @data = nil
    end

    # Load and validate the configuration file.
    #
    # @return [Mammoth::Configuration] self
    # @raise [Mammoth::ConfigurationError] when validation fails
    def load
      raise ConfigurationError, "configuration file not found: #{path}" unless File.file?(path)

      @data = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
      raise ConfigurationError, "configuration must be a YAML mapping" unless data.is_a?(Hash)

      validate_schema!
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
  end
end
