# frozen_string_literal: true

require "json"

module Mammoth
  # Small command dispatcher for Mammoth's operator-facing CLI.
  class CLI
    # Internal replay envelope used for transaction dead-letter recovery.
    DEAD_LETTER_TRANSACTION_ENVELOPE = Data.define(
      :events,
      :transaction_id,
      :source_position,
      :commit_lsn,
      :committed_at,
      :metadata
    )

    # Human-readable command usage printed for invalid or incomplete invocations.
    USAGE = [
      "Usage:",
      "  mammoth version",
      "  mammoth validate CONFIG",
      "  mammoth bootstrap CONFIG",
      "  mammoth status CONFIG",
      "  mammoth start CONFIG",
      "  mammoth deliver-sample CONFIG EVENT_JSON",
      "  mammoth dead-letters list CONFIG [--status STATUS] [--destination NAME] " \
      "[--failed-after ISO8601] [--failed-before ISO8601] [--limit N]",
      "  mammoth dead-letters show CONFIG ID",
      "  mammoth dead-letters replay CONFIG [ID ...] [--destination NAME] [--status STATUS] " \
      "[--failed-after ISO8601] [--failed-before ISO8601] [--limit N]",
      "  mammoth observability CONFIG"
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
      when "dead-letters" then dead_letters
      when "observability" then observability
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
      require_config_path!
      Commands::ValidateCommand.new(config_provider).call
    end

    def bootstrap
      Commands::BootstrapCommand.new(load_config).call
    end

    def status
      config = load_config
      store = SQLiteStore.connect(config.dig("sqlite", "path"))
      Commands::StatusCommand.new(config, sqlite_store: store).call
    end

    def start
      Commands::StartCommand.new(load_config).call
    end

    def deliver_sample
      config = load_config
      event_path = argv.fetch(2, nil)
      raise ConfigurationError, "event JSON path required\n#{USAGE}" unless event_path

      Commands::DeliverSampleCommand.new(config, event_path: event_path).call
    end

    # Dispatch the nested dead-letter command group.
    #
    # @return [Integer] process status code
    def dead_letters
      Commands::DeadLettersCommand.new(argv).call
    end

    def observability
      config = load_config
      server = ObservabilityServer.new(config)
      puts "Mammoth observability listening on #{server.host}:#{server.port}"
      server.start
      0
    end

    def load_config
      require_config_path!

      config_provider.load
    end

    def require_config_path!
      raise ConfigurationError, "configuration path required\n#{USAGE}" unless config_path
    end

    def config_provider
      Configuration::Providers::FileProvider.new(config_path)
    end
  end
end
