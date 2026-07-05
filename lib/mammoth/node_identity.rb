# frozen_string_literal: true

require "socket"

module Mammoth
  # Local Mammoth node identity used by status and future control-plane agents.
  class NodeIdentity
    attr_reader :node_id, :node_name, :fleet_id, :environment, :labels, :metadata

    # @param node_id [String] stable node identifier
    # @param node_name [String] human-readable node name
    # @param fleet_id [String, nil] optional fleet identifier
    # @param environment [String, nil] optional environment name
    # @param labels [Hash] operator-defined labels
    # @param metadata [Hash] operator-defined metadata
    def initialize(node_id:, node_name:, fleet_id: nil, environment: nil, labels: {}, metadata: {})
      @node_id = node_id
      @node_name = node_name
      @fleet_id = fleet_id
      @environment = environment
      @labels = labels || {}
      @metadata = metadata || {}
    end

    # Build identity from Mammoth configuration.
    #
    # @param config [Mammoth::Configuration] loaded configuration
    # @return [Mammoth::NodeIdentity]
    def self.from_config(config)
      identity = config.data["node"] || {}
      hostname = Socket.gethostname
      new(
        node_id: identity["node_id"] || hostname,
        node_name: identity["node_name"] || config.dig("mammoth", "name") || hostname,
        fleet_id: identity["fleet_id"],
        environment: identity["environment"],
        labels: identity["labels"] || {},
        metadata: identity["metadata"] || {}
      )
    end

    # @return [Hash] JSON-friendly node identity
    def to_h
      {
        node_id: node_id,
        node_name: node_name,
        fleet_id: fleet_id,
        environment: environment,
        labels: labels,
        metadata: metadata
      }
    end
  end
end
