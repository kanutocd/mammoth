# frozen_string_literal: true

module Mammoth
  module Runtimes
    # Inline runtime adapter that processes work in the caller thread.
    class InlineAdapter < Adapter
      attr_reader :processor, :observer

      # @param processor [#process] delivery processor
      # @param observer [CDC::Core::Observer] dispatch lifecycle observer
      def initialize(processor:, observer: CDC::Core::Observer.new)
        super()
        @processor = processor
        @observer = observer
      end

      # Build an inline runtime.
      #
      # @param processor [#process] delivery processor
      # @return [Mammoth::Runtimes::InlineAdapter]
      def self.build(processor:, observer: CDC::Core::Observer.new, **_options)
        new(processor: processor, observer: observer)
      end

      # @return [String] adapter type name
      def self.adapter_type
        "inline"
      end

      # @param items [Array<Object>] work units
      # @return [Array<Object>] processor results
      def process_many(items)
        items.map do |item|
          observer.dispatch_started(item)
          processor.process(item).tap { |result| observe_result(result) }
        end
      end

      # @return [nil]
      def shutdown
        nil
      end

      private

      def observe_result(result)
        return observer.dispatch_succeeded(result) if result.success?
        return observer.dispatch_failed(result) if result.failure?

        observer.dispatch_skipped(result)
      end
    end
  end
end
