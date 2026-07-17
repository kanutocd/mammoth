# frozen_string_literal: true

module Mammoth
  # Local command objects shared by CLI and future control-plane agents.
  module Commands
    # Reusable local command object for status inspection.
    class StatusCommand
      attr_reader :config, :state_adapter, :output

      # @param config [Mammoth::Configuration] loaded configuration
      # @param state_adapter [Mammoth::OperationalState::Adapter, nil] operational state dependency
      # @param output [#puts] output stream
      def initialize(config, state_adapter: nil, output: $stdout)
        @config = config
        @state_adapter = state_adapter || OperationalState::Registry.build_configured(config)
        @output = output
      end

      # Execute the status command.
      #
      # @return [Integer] process-style status code
      def call
        Status.call(config, state_adapter: state_adapter, output: output)
        0
      end
    end
  end
end
