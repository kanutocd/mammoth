# frozen_string_literal: true

module Mammoth
  module Commands
    # Reusable local command object for dead-letter inspection and replay.
    class DeadLettersCommand
      attr_reader :argv, :state_adapter, :lifecycle_hooks

      # @param argv [Array<String>] dead-letters CLI-style arguments
      # @param state_adapter [Mammoth::OperationalState::Adapter, nil] operational state dependency
      # @param lifecycle_hooks [Mammoth::LifecycleHooks, Hash] local lifecycle callbacks
      def initialize(argv, state_adapter: nil, lifecycle_hooks: LifecycleHooks.new)
        @argv = argv
        @state_adapter = state_adapter
        @lifecycle_hooks = lifecycle_hooks
      end

      # @return [Integer] process-style status code
      def call
        DeadLetterCommands.call(argv, state_adapter: state_adapter, lifecycle_hooks: lifecycle_hooks)
      end
    end
  end
end
