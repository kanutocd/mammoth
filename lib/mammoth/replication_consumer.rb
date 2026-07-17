# frozen_string_literal: true

module Mammoth
  # Consumes normalized CDC work from an injected source.
  #
  # ReplicationConsumer is intentionally upstream-agnostic. It does not know
  # which upstream system produced the work. Its
  # job is to consume CDC Ecosystem work and yield either individual change
  # events or transaction envelopes depending on Mammoth's configured delivery
  # unit.
  class ReplicationConsumer
    attr_reader :source, :delivery_unit

    # @param source [#each, nil] injectable CDC work stream
    # @param delivery_unit [String, Symbol] :event or :transaction
    def initialize(source: nil, delivery_unit: :event)
      @source = source
      @delivery_unit = delivery_unit.to_sym
    end

    # Consume normalized CDC work from the configured source.
    #
    # @yieldparam event [CDC::Core::ChangeEvent, CDC::Core::TransactionEnvelope] core work item
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
      return work.flat_map { |item| flatten_cdc_work(item) } if work.is_a?(Array)
      return transaction_work(work) if work.is_a?(CDC::Core::TransactionEnvelope)
      return event_work(work) if work.is_a?(CDC::Core::ChangeEvent)

      raise ReplicationError, "CDC source yielded non-core work: #{work.class}"
    end

    def transaction_delivery?
      delivery_unit == :transaction
    end

    def transaction_work(envelope)
      transaction_delivery? ? [envelope] : envelope.events
    end

    def event_work(event)
      transaction_delivery? ? [transaction_envelope(event)] : [event]
    end

    def transaction_envelope(event)
      CDC::Core::TransactionEnvelope.new(
        transaction_id: event.transaction_id || event.metadata[:event_id] || event.commit_lsn,
        events: [event],
        commit_lsn: event.commit_lsn,
        committed_at: event.occurred_at,
        metadata: event.metadata
      )
    end
  end
end
