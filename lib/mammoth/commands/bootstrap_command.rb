# frozen_string_literal: true

module Mammoth
  module Commands
    # Initializes the configured operational-state backend.
    class BootstrapCommand
      attr_reader :config, :state_adapter, :output

      # @param config [Mammoth::Configuration] loaded configuration
      # @param state_adapter [Mammoth::OperationalState::Adapter, nil] operational state dependency
      # @param output [#puts] output stream
      def initialize(config, state_adapter: nil, output: $stdout)
        @config = config
        @state_adapter = state_adapter || OperationalState::Registry.build_configured(config)
        @output = output
      end

      # @return [Integer] process-style status code
      def call
        state_adapter.bootstrap!
        summary = state_adapter.summary
        output.puts "Operational state initialized"
        output.puts "Adapter: #{summary.fetch(:adapter)}"
        output.puts "Path: #{summary.fetch(:path)}" if summary.key?(:path)
        output.puts "Tables: #{Array(summary.fetch(:tables)).join(", ")}" if summary.key?(:tables)
        0
      end
    end
  end
end
