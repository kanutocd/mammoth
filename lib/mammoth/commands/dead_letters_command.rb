# frozen_string_literal: true

module Mammoth
  module Commands
    # Reusable local command object for dead-letter inspection and replay.
    class DeadLettersCommand
      attr_reader :argv, :lifecycle_hooks

      # @param argv [Array<String>] dead-letters CLI-style arguments
      # @param lifecycle_hooks [Mammoth::LifecycleHooks, Hash] local lifecycle callbacks
      def initialize(argv, lifecycle_hooks: LifecycleHooks.new)
        @argv = argv
        @lifecycle_hooks = lifecycle_hooks
      end

      # @return [Integer] process-style status code
      def call
        DeadLetterCommands.call(argv, lifecycle_hooks: lifecycle_hooks)
      end
    end
  end
end
