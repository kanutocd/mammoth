# frozen_string_literal: true

require "json"
require "time"

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

    attr_reader :argv, :lifecycle_hooks

    # @param argv [Array<String>] command line arguments
    def self.call(argv, lifecycle_hooks: LifecycleHooks.new)
      new(argv, lifecycle_hooks: lifecycle_hooks).call
    end

    # @param argv [Array<String>] command line arguments
    # @param lifecycle_hooks [Mammoth::LifecycleHooks, Hash] local lifecycle callbacks
    def initialize(argv, lifecycle_hooks: LifecycleHooks.new)
      @argv = argv
      @lifecycle_hooks = lifecycle_hooks.is_a?(LifecycleHooks) ? lifecycle_hooks : LifecycleHooks.new(lifecycle_hooks)
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
      options = list_options
      rows = dead_letter_store.rows(
        status: options.fetch(:status),
        destination: options.fetch(:destination),
        failed_after: options.fetch(:failed_after),
        failed_before: options.fetch(:failed_before),
        limit: options.fetch(:limit)
      )
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

      lifecycle_hooks.call(:before_replay, replay_context(rows: rows))
      rows.each do |row|
        result = replay_row(row)
        dead_letter_store.resolve(row.fetch("id")) if replay_resolved?(result)
        puts replay_message(row, result)
      end
      lifecycle_hooks.call(:after_replay, replay_context(rows: rows))
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
      options = { status: "pending", destination: nil, failed_after: nil, failed_before: nil, limit: 100 }
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
        assign_option(args, index, options, :status)
      when "--destination"
        assign_option(args, index, options, :destination)
      when "--failed-after"
        assign_time_option(args, index, options, :failed_after)
      when "--failed-before"
        assign_time_option(args, index, options, :failed_before)
      when "--limit"
        assign_limit_option(args, index, options)
      else
        raise ConfigurationError, "unknown option #{args[index]}\n#{CLI::USAGE}" if args[index].start_with?("--")

        raise ConfigurationError, "unexpected argument #{args[index]}\n#{CLI::USAGE}"
      end
    rescue IndexError
      raise ConfigurationError, "missing value for dead letter option"
    end

    def assign_option(args, index, options, key)
      options[key] = args.fetch(index + 1)
      index + 2
    end

    def assign_time_option(args, index, options, key)
      options[key] = parse_time_option(args.fetch(index + 1), args.fetch(index))
      index + 2
    end

    def assign_limit_option(args, index, options)
      options[:limit] = parse_limit_option(args.fetch(index + 1))
      index + 2
    end

    def parse_limit_option(value)
      Integer(value)
    rescue ArgumentError
      raise ConfigurationError, "dead letter limit must be an integer"
    end

    # Resolve the rows that should be replayed.
    #
    # @return [Array<Hash>] replay rows
    def replay_rows
      options = replay_options
      ids = options.fetch(:ids)
      if ids.empty?
        return dead_letter_store.rows(
          status: options.fetch(:status),
          destination: options.fetch(:destination),
          failed_after: options.fetch(:failed_after),
          failed_before: options.fetch(:failed_before),
          limit: options.fetch(:limit)
        )
      end

      ids.map do |raw_id|
        id = raw_id
        row = dead_letter_store.fetch(id)
        raise ConfigurationError, "dead letter not found: #{id}" unless row

        row
      end
    end

    def parse_time_option(value, option_name)
      Time.iso8601(value).utc.iso8601
    rescue ArgumentError
      raise ConfigurationError, "#{option_name} must be an ISO-8601 timestamp"
    end

    def replay_options
      ids = [] # : Array[Integer]
      options = { ids: ids, status: "pending", destination: nil, failed_after: nil, failed_before: nil, limit: 100 }
      index = 0
      args = argv.drop(3)

      # rubocop:disable Style/WhileUntilModifier
      while index < args.length
        index = parse_replay_option(args, index, options)
      end
      # rubocop:enable Style/WhileUntilModifier

      options
    end

    def parse_replay_option(args, index, options)
      case args.fetch(index)
      when "--status", "--destination", "--failed-after", "--failed-before", "--limit"
        parse_list_option(args, index, options)
      else
        raise ConfigurationError, "unexpected argument #{args[index]}\n#{CLI::USAGE}" if args[index].start_with?("--")

        options[:ids] << Integer(args.fetch(index))
        index + 1
      end
    rescue ArgumentError
      raise ConfigurationError, "dead letter id must be an integer"
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

    def replay_resolved?(result)
      result.fetch(:status) == "delivered" || result.fetch(:duplicate, false)
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

    def replay_context(extra = {})
      {
        config: load_config,
        dead_letter_store: dead_letter_store,
        delivery_worker: worker
      }.merge(extra)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
