# frozen_string_literal: true

module Mammoth
  # Consumes CDC-core work items from Mammoth's configured replication source.
  #
  # ReplicationConsumer is the boundary between upstream CDC ingestion and
  # sink delivery. Live PostgreSQL ingestion is delegated to {PgoutputSource};
  # injected sources remain available for unit tests, demos, and e2e fixtures.
  class ReplicationConsumer
    attr_reader :config, :source, :adapter

    # @param config [Mammoth::Configuration] loaded configuration
    # @param source [#each, nil] injectable CDC work stream
    # @param adapter [#call, nil] optional adapter for injected raw events
    def initialize(config, source: nil, adapter: nil)
      @config = config
      @source = source
      @adapter = adapter
    end

    # Return the configured replication slot.
    #
    # @return [String]
    def slot
      config.dig("replication", "slot")
    end

    # Return the configured publication.
    #
    # @return [String]
    def publication
      config.dig("replication", "publication")
    end

    # Consume normalized CDC work from the configured source.
    #
    # @yieldparam event [Object] CDC::Core::ChangeEvent-compatible event
    # @return [Integer] number of consumed events
    def start
      return enum_for(:start) unless block_given?

      count = 0
      each_event do |event|
        yield event
        count += 1
      end
      count
    end

    private

    def each_event
      effective_source.each do |raw_work|
        normalize(raw_work).each { |event| yield event }
      end
    end

    def effective_source
      source || PgoutputSource.new(config)
    end

    def normalize(raw_work)
      adapted = adapter ? adapter.call(raw_work) : raw_work
      flatten_cdc_work(adapted)
    end

    def flatten_cdc_work(work)
      if transaction_envelope?(work)
        work.events
      else
        Array(work).flat_map { |item| transaction_envelope?(item) ? item.events : item }
      end
    end

    def transaction_envelope?(work)
      work.respond_to?(:events) && work.respond_to?(:transaction_id)
    end
  end
end
