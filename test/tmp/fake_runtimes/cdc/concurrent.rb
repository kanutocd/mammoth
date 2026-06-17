# frozen_string_literal: true

module CDC
  module Concurrent
    class ProcessorPool
      class << self
        attr_reader :last_options
      end

      def initialize(processor:, concurrency:, timeout:, preserve_order:)
        @processor = processor
        @shutdown = false
        self.class.instance_variable_set(
          :@last_options,
          { processor: processor, concurrency: concurrency, timeout: timeout, preserve_order: preserve_order }
        )
      end

      def process_many(items)
        items.map { |item| @processor.process(item) }.freeze
      end

      def shutdown
        @shutdown = true
      end
    end
  end
end
