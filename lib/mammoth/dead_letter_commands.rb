# frozen_string_literal: true

require "json"

module Mammoth
  # Operator commands for inspecting and replaying dead letters.
  # rubocop:disable Metrics/ClassLength
  class DeadLetterCommands
    # Internal replay envelope used for transaction dead-letter recovery.
    DEAD_LETTER_TRANSACTION_ENVELOPE = Data.define(
      :events,
      :transaction_id,
      :source_position,
      :commit_lsn,
      :committed_at,
      :metadata
    )

    attr_reader :argv

    # @param argv [Array<String>] command line arguments
    def self.call(argv)
      new(argv).call
    end

    # @param argv [Array<String>] command line arguments
    def initialize(argv)
      @argv = argv
    end

    # Dispatch the nested dead-letter subcommand.
    #
    # @return [Integer] process status code
    def call
      case command
      when "list" then list
      when "show" then show
      when "replay" then replay
      else
        raise ConfigurationError, "dead-letters subcommand required\n#{CLI::USAGE}"
      end
    rescue Mammoth::Error => e
      warn e.message
      1
    end

    private

    def command
      argv.fetch(1, nil)
    end

    def config_path
      argv.fetch(2, nil)
    end

    def list
      rows = dead_letter_store.rows(status: list_options.fetch(:status), limit: list_options.fetch(:limit))
      puts list_header
      rows.each { |row| puts list_row(row) }
      0
    end

    def show
      row = fetch_dead_letter!(dead_letter_id)
      puts JSON.pretty_generate(show_payload(row))
      0
    end

    def replay
      rows = replay_rows
      raise ConfigurationError, "no dead letters found to replay" if rows.empty?

      rows.each do |row|
        result = replay_row(row)
        dead_letter_store.resolve(row.fetch("id")) unless result.fetch(:status) == "dead_lettered"
        puts replay_message(row, result)
      end
      0
    end

    def load_config
      raise ConfigurationError, "configuration path required\n#{CLI::USAGE}" unless config_path

      Configuration.load(config_path)
    end

    def dead_letter_store
      @dead_letter_store ||= DeadLetterStore.new(SQLiteStore.connect(load_config.dig("sqlite", "path")).bootstrap!)
    end

    def worker
      @worker ||= Application.new(load_config).delivery_worker
    end

    def dead_letter_id
      raw_id = argv.fetch(3, nil)
      raise ConfigurationError, "dead letter id required\n#{CLI::USAGE}" unless raw_id

      Integer(raw_id)
    rescue ArgumentError
      raise ConfigurationError, "dead letter id must be an integer"
    end

    # Parse dead-letter list filters and pagination.
    #
    # @return [Hash] list options
    def list_options
      options = { status: "pending", limit: 100 }
      index = 0
      args = argv.drop(3)

      # rubocop:disable Style/WhileUntilModifier
      while index < args.length
        index = parse_list_option(args, index, options)
      end
      # rubocop:enable Style/WhileUntilModifier

      options
    end

    def parse_list_option(args, index, options)
      case args.fetch(index)
      when "--status"
        options[:status] = args.fetch(index + 1)
        index + 2
      when "--limit"
        options[:limit] = Integer(args.fetch(index + 1))
        index + 2
      else
        raise ConfigurationError, "unknown option #{args[index]}\n#{CLI::USAGE}" if args[index].start_with?("--")

        raise ConfigurationError, "unexpected argument #{args[index]}\n#{CLI::USAGE}"
      end
    rescue ArgumentError, IndexError
      raise ConfigurationError, "dead letter limit must be an integer"
    end

    # Resolve the rows that should be replayed.
    #
    # @return [Array<Hash>] replay rows
    def replay_rows
      ids = argv.drop(3)
      return dead_letter_store.pending if ids.empty?

      ids.map do |raw_id|
        id = Integer(raw_id)
        row = dead_letter_store.fetch(id)
        raise ConfigurationError, "dead letter not found: #{id}" unless row

        row
      rescue ArgumentError
        raise ConfigurationError, "dead letter id must be an integer"
      end
    end

    def fetch_dead_letter!(id)
      row = dead_letter_store.fetch(id)
      raise ConfigurationError, "dead letter not found: #{id}" unless row

      row
    end

    def replay_row(row)
      payload = JSON.parse(row.fetch("payload_json"))
      if transaction_payload?(payload)
        replay_transaction(row.fetch("destination_name"), transaction_envelope(payload))
      else
        replay_event(row.fetch("destination_name"), payload)
      end
    end

    def replay_event(destination_name, payload)
      return worker.deliver_to(destination_name, payload) if worker.respond_to?(:deliver_to)

      worker.deliver(payload)
    end

    def replay_transaction(destination_name, envelope)
      return worker.deliver_transaction_to(destination_name, envelope) if worker.respond_to?(:deliver_transaction_to)

      worker.deliver_transaction(envelope)
    end

    def transaction_payload?(payload)
      payload.fetch("type", nil) == TransactionEnvelopeSerializer::PAYLOAD_TYPE
    end

    def transaction_envelope(payload)
      DEAD_LETTER_TRANSACTION_ENVELOPE.new(
        payload.fetch("events"),
        payload.fetch("transaction_id"),
        payload["source_position"],
        payload["commit_lsn"],
        payload["committed_at"],
        payload["metadata"] || {}
      )
    end

    def show_payload(row)
      row.merge("payload" => JSON.parse(row.fetch("payload_json")))
    end

    def list_header
      format(
        "%<id>-4s  %<status>-10s  %<destination>-18s  %<retries>-8s  %<failed_at>-19s  %<event>s",
        id: "ID",
        status: "STATUS",
        destination: "DESTINATION",
        retries: "RETRIES",
        failed_at: "FAILED_AT",
        event: "EVENT"
      )
    end

    def list_row(row)
      format(
        "%<id>-4s  %<status>-10s  %<destination>-18s  %<retries>-8s  %<failed_at>-19s  %<event>s",
        id: row.fetch("id"),
        status: row.fetch("status"),
        destination: row.fetch("destination_name"),
        retries: row.fetch("retry_count"),
        failed_at: row.fetch("failed_at"),
        event: row.fetch("event_id")
      )
    end

    def replay_message(row, result)
      "Dead letter #{row.fetch("id")}: #{result.fetch(:status)}"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
