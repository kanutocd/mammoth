# frozen_string_literal: true

module Mammoth
  module Commands
    # Initializes the configured operational SQLite database.
    class BootstrapCommand
      attr_reader :config, :output

      # @param config [Mammoth::Configuration] loaded configuration
      # @param output [#puts] output stream
      def initialize(config, output: $stdout)
        @config = config
        @output = output
      end

      # @return [Integer] process-style status code
      def call
        store = SQLiteStore.connect(config.dig("sqlite", "path")).bootstrap!
        output.puts "SQLite database initialized"
        output.puts "Path: #{store.path}"
        output.puts "Tables: #{store.tables.join(", ")}"
        0
      end
    end
  end
end
