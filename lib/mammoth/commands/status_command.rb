# frozen_string_literal: true

module Mammoth
  # Local command objects shared by CLI and future control-plane agents.
  module Commands
    # Reusable local command object for status inspection.
    class StatusCommand
      attr_reader :config, :sqlite_store, :output

      # @param config [Mammoth::Configuration] loaded configuration
      # @param sqlite_store [Mammoth::SQLiteStore, nil] optional operational store
      # @param output [#puts] output stream
      def initialize(config, sqlite_store: nil, output: $stdout)
        @config = config
        @sqlite_store = sqlite_store
        @output = output
      end

      # Execute the status command.
      #
      # @return [Integer] process-style status code
      def call
        Status.call(config, sqlite_store: sqlite_store, output: output)
        0
      end
    end
  end
end
