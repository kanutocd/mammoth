# frozen_string_literal: true

module Mammoth
  module Commands
    # Starts a Mammoth application and prints the processed work count.
    class StartCommand
      attr_reader :config, :source, :output, :lifecycle_hooks

      # @param config [Mammoth::Configuration] loaded configuration
      # @param source [#each, nil] optional injected source
      # @param output [#puts] output stream
      # @param lifecycle_hooks [Mammoth::LifecycleHooks, Hash] local lifecycle callbacks
      def initialize(config, source: nil, output: $stdout, lifecycle_hooks: LifecycleHooks.new)
        @config = config
        @source = source
        @output = output
        @lifecycle_hooks = lifecycle_hooks
      end

      # @return [Integer] process-style status code
      def call
        processed = Application.new(config, source: source, lifecycle_hooks: lifecycle_hooks).start
        output.puts "Processed events: #{processed}"
        0
      end
    end
  end
end
