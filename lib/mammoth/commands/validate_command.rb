# frozen_string_literal: true

module Mammoth
  module Commands
    # Validates a Mammoth configuration through a provider.
    class ValidateCommand
      attr_reader :provider, :output

      # @param provider [#load] configuration provider
      # @param output [#puts] output stream
      def initialize(provider, output: $stdout)
        @provider = provider
        @output = output
      end

      # @return [Integer] process-style status code
      def call
        config = provider.load
        output.puts "Configuration OK: #{config.path}"
        0
      end
    end
  end
end
