# frozen_string_literal: true

module Mammoth
  # Builds and prints a boring operational status snapshot.
  class Status
    attr_reader :config, :state_adapter, :output

    # Print status for a configuration and optional operational-state adapter.
    #
    # @param config [Mammoth::Configuration] loaded configuration
    # @param state_adapter [Mammoth::OperationalState::Adapter, nil] operational state dependency
    # @return [void]
    def self.call(config, state_adapter: nil, output: $stdout)
      new(config, state_adapter: state_adapter, output: output).call
    end

    # @param config [Mammoth::Configuration] loaded configuration
    # @param state_adapter [Mammoth::OperationalState::Adapter, nil] operational state dependency
    # @param output [#puts] output stream
    def initialize(config, state_adapter: nil, output: $stdout)
      @config = config
      @state_adapter = state_adapter
      @output = output
    end

    # Print the status snapshot.
    #
    # @return [void]
    def call
      status_lines.each { |line| output.puts(line) }
      print_store_state if state_adapter
    end

    private

    def status_lines
      identity_lines + replication_lines + runtime_lines + destination_lines
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
      output.puts "Operational state ready: #{state_adapter.ready?}"
      state_adapter.summary.each do |key, value|
        output.puts "#{status_label(key)}: #{format_status_value(value)}"
      end
    end

    def status_label(key)
      key.to_s.split("_").map(&:capitalize).join(" ")
    end

    def format_status_value(value)
      value.is_a?(Array) ? value.join(", ") : value
    end
  end
end
