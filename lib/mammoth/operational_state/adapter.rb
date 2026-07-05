# frozen_string_literal: true

module Mammoth
  # Operational state adapter contracts and registry.
  module OperationalState
    # Base contract for operational state adapters.
    class Adapter
      # @return [void]
      def initialize; end

      # @return [Mammoth::CheckpointStore]
      def checkpoint_store
        raise NotImplementedError, "#{self.class} must implement #checkpoint_store"
      end

      # @return [Mammoth::DeadLetterStore]
      def dead_letter_store
        raise NotImplementedError, "#{self.class} must implement #dead_letter_store"
      end

      # @return [Mammoth::DeliveredEnvelopeStore]
      def delivered_envelope_store
        raise NotImplementedError, "#{self.class} must implement #delivered_envelope_store"
      end

      # @return [Hash] JSON-friendly state summary
      def summary
        {
          adapter: "unknown",
          checkpoints: checkpoint_store.count,
          dead_letters: dead_letter_store.count,
          delivered_envelopes: delivered_envelope_store.count
        }
      end
    end
  end
end
