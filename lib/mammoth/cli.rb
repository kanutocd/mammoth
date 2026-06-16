# frozen_string_literal: true

require "json"

module Mammoth
  # Small command dispatcher for Mammoth's operator-facing CLI.
  class CLI
    # Human-readable command usage printed for invalid or incomplete invocations.
    USAGE = [
      "Usage:",
      "  mammoth version",
      "  mammoth validate CONFIG",
      "  mammoth bootstrap CONFIG",
      "  mammoth status CONFIG",
      "  mammoth start CONFIG",
      "  mammoth deliver-sample CONFIG EVENT_JSON"
    ].join("\n")

    # Run the CLI.
    #
    # @param argv [Array<String>] command line arguments
    # @return [Integer] process status code
    def self.call(argv)
      new(argv).call
    end

    attr_reader :argv

    # @param argv [Array<String>] command line arguments
    def initialize(argv)
      @argv = argv
    end

    # Dispatch the requested command.
    #
    # @return [Integer] process status code
    def call
      case command
      when "version" then version
      when "validate" then validate
      when "bootstrap" then bootstrap
      when "status" then status
      when "start" then start
      when "deliver-sample" then deliver_sample
      else
        warn USAGE
        1
      end
    rescue Mammoth::Error => e
      warn e.message
      1
    end

    private

    def command
      argv.fetch(0, nil)
    end

    def config_path
      argv.fetch(1, nil)
    end

    def version
      puts "Mammoth #{Mammoth::VERSION}"
      0
    end

    def validate
      load_config
      puts "Configuration OK: #{config_path}"
      0
    end

    def bootstrap
      config = load_config
      store = SQLiteStore.connect(config.dig("sqlite", "path")).bootstrap!
      puts "SQLite database initialized"
      puts "Path: #{store.path}"
      puts "Tables: #{store.tables.join(", ")}"
      0
    end

    def status
      config = load_config
      store = SQLiteStore.connect(config.dig("sqlite", "path"))
      Status.call(config, sqlite_store: store)
      0
    end

    def start
      processed = Application.new(load_config).start
      puts "Delivered events: #{processed}"
      0
    end

    def deliver_sample
      config = load_config
      event_path = argv.fetch(2, nil)
      raise ConfigurationError, "event JSON path required\n#{USAGE}" unless event_path
      raise ConfigurationError, "event JSON file not found: #{event_path}" unless File.file?(event_path)

      event = JSON.parse(File.read(event_path))
      processed = Application.new(config, source: [event]).start
      puts "Delivered sample events: #{processed}"
      0
    rescue JSON::ParserError => e
      raise ConfigurationError, "invalid event JSON in #{event_path}: #{e.message}"
    end

    def load_config
      raise ConfigurationError, "configuration path required\n#{USAGE}" unless config_path

      Configuration.load(config_path)
    end
  end
end
