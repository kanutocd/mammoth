# frozen_string_literal: true

module Mammoth
  # Builds and prints a boring operational status snapshot.
  class Status
    attr_reader :config, :sqlite_store, :output

    # Print status for a configuration and optional SQLite store.
    #
    # @param config [Mammoth::Configuration] loaded configuration
    # @param sqlite_store [Mammoth::SQLiteStore, nil] operational store
    # @return [void]
    def self.call(config, sqlite_store: nil, output: $stdout)
      new(config, sqlite_store: sqlite_store, output: output).call
    end

    # @param config [Mammoth::Configuration] loaded configuration
    # @param sqlite_store [Mammoth::SQLiteStore, nil] operational store
    # @param output [#puts] output stream
    def initialize(config, sqlite_store: nil, output: $stdout)
      @config = config
      @sqlite_store = sqlite_store
      @output = output
    end

    # Print the status snapshot.
    #
    # @return [void]
    def call
      status_lines.each { |line| output.puts(line) }
      print_store_state if sqlite_store
    end

    private

    def status_lines
      identity_lines + replication_lines + runtime_lines + destination_lines + ["SQLite: #{sqlite_path}"]
    end

    def identity_lines
      [
        "Mammoth: #{config.dig("mammoth", "name")}",
        "Node ID: #{node_identity.node_id}",
        "Node name: #{node_identity.node_name}",
        "Fleet: #{node_identity.fleet_id || "unassigned"}",
        "Environment: #{node_identity.environment || "unspecified"}"
      ]
    end

    def replication_lines
      [
        "Replication slot: #{config.dig("replication", "slot")}",
        "Replication publications: #{Array(config.dig("replication", "publications")).join(", ")}"
      ]
    end

    def runtime_lines
      [
        "Runtime: not started",
        "Runtime adapter: #{capabilities.fetch(:runtime)}",
        "Operational state: #{capabilities.fetch(:operational_state)}"
      ]
    end

    def destination_lines
      [
        "Destinations: #{destination_names.join(", ")}",
        "Destination adapters: #{capabilities.fetch(:destinations).join(", ")}",
        "Features: #{capabilities.fetch(:features).join(", ")}"
      ]
    end

    def sqlite_path
      config.dig("sqlite", "path")
    end

    def destination_names
      destinations = config.data["destinations"]
      return destinations.map { |destination| destination.fetch("name") } if destinations

      [config.dig("webhook", "name")]
    end

    def node_identity
      @node_identity ||= NodeIdentity.from_config(config)
    end

    def capabilities
      @capabilities ||= Capabilities.call(config)
    end

    def print_store_state
      store = sqlite_store.bootstrap!
      output.puts "Tables: #{store.tables.join(", ")}"
      output.puts "Checkpoints: #{CheckpointStore.new(store).count}"
      output.puts "Dead Letters: #{DeadLetterStore.new(store).count}"
    end
  end
end
