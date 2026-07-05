# frozen_string_literal: true

module Mammoth
  module Runtimes
    # Inline runtime adapter that processes work in the caller thread.
    class InlineAdapter < Adapter
      attr_reader :processor

      # @param processor [#process] delivery processor
      def initialize(processor:)
        super()
        @processor = processor
      end

      # Build an inline runtime.
      #
      # @param processor [#process] delivery processor
      # @return [Mammoth::Runtimes::InlineAdapter]
      def self.build(processor:, **_options)
        new(processor: processor)
      end

      # @return [String] adapter type name
      def self.adapter_type
        "inline"
      end

      # @param items [Array<Object>] work units
      # @return [Array<Object>] processor results
      def process_many(items)
        items.map { |item| processor.process(item) }
      end

      # @return [nil]
      def shutdown
        nil
      end
    end
  end
end
