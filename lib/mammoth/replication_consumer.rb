# frozen_string_literal: true

module Mammoth
  # Consumes normalized CDC work from an injected source.
  #
  # ReplicationConsumer is intentionally upstream-agnostic. It does not know
  # which upstream system produced the work. Its
  # only job is to consume CDC Ecosystem work, flatten CDC transaction
  # envelopes, and yield individual change events to the delivery pipeline.
  class ReplicationConsumer
    attr_reader :source

    # @param source [#each, nil] injectable CDC work stream
    def initialize(source: nil)
      @source = source
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

    def each_event(&block)
      effective_source.each do |work|
        flatten_cdc_work(work).each(&block)
      end
    end

    def effective_source
      source || raise(ReplicationError, "replication source is not configured")
    end

    def flatten_cdc_work(work)
      return [] if work.nil?
      return validate_events(work.events) if transaction_envelope?(work)
      return work.flat_map { |item| flatten_cdc_work(item) } if work.is_a?(Array)

      validate_events([work])
    end

    def validate_events(events)
      events.each { |event| validate_cdc_event!(event) }
    end

    def validate_cdc_event!(event)
      return event if event.respond_to?(:to_h) && cdc_event_hash?(event.to_h)

      raise ReplicationError, "CDC source yielded non-CDC work: #{event.class}"
    end

    def cdc_event_hash?(event_hash)
      return false unless event_hash.respond_to?(:key?)

      has_operation = event_hash.key?("operation") || event_hash.key?(:operation)
      has_position = event_hash.key?("source_position") || event_hash.key?(:source_position) ||
                     event_hash.key?("commit_lsn") || event_hash.key?(:commit_lsn)
      has_operation && has_position
    end

    def transaction_envelope?(work)
      work.respond_to?(:events) && work.respond_to?(:transaction_id)
    end
  end
end
