# frozen_string_literal: true

module Mammoth
  # Delivers normalized events with retry, checkpoint, and dead-letter handling.
  #
  # DeliveryWorker is Mammoth's first reliable delivery unit. It intentionally keeps
  # the delivery contract small: attempt webhook delivery, advance the checkpoint
  # after success, and persist the failed event to the dead letter queue after
  # retry exhaustion.
  class DeliveryWorker
    # Default source name used when an event does not provide one.
    DEFAULT_SOURCE = "postgresql"

    attr_reader :sink, :checkpoint_store, :dead_letter_store, :retry_schedule, :max_attempts, :sleeper, :source_name,
                :slot_name, :publication_name

    # @param sink [#deliver] destination sink
    # @param checkpoint_store [Mammoth::CheckpointStore] checkpoint persistence
    # @param dead_letter_store [Mammoth::DeadLetterStore] dead letter persistence
    # @param source_name [String] logical source name
    # @param slot_name [String] replication slot name
    # @param publication_name [String] publication name
    # @param max_attempts [Integer] maximum delivery attempts
    # @param retry_schedule [Array<Integer>] retry wait schedule in seconds
    # @param sleeper [#call] sleep strategy, injectable for tests
    def initialize(sink:, checkpoint_store:, dead_letter_store:, source_name:, slot_name:, publication_name:,
                   max_attempts:, retry_schedule:, sleeper: Kernel.method(:sleep))
      @sink = sink
      @checkpoint_store = checkpoint_store
      @dead_letter_store = dead_letter_store
      @source_name = source_name
      @slot_name = slot_name
      @publication_name = publication_name
      @max_attempts = max_attempts
      @retry_schedule = retry_schedule
      @sleeper = sleeper
    end

    # Build a delivery worker from Mammoth configuration and stores.
    #
    # @param config [Mammoth::Configuration] loaded configuration
    # @param sink [#deliver] destination sink
    # @param checkpoint_store [Mammoth::CheckpointStore] checkpoint persistence
    # @param dead_letter_store [Mammoth::DeadLetterStore] dead letter persistence
    # @param sleeper [#call] sleep strategy
    # @return [Mammoth::DeliveryWorker]
    def self.from_config(config, sink:, checkpoint_store:, dead_letter_store:, sleeper: Kernel.method(:sleep))
      new(
        sink: sink,
        checkpoint_store: checkpoint_store,
        dead_letter_store: dead_letter_store,
        source_name: config.dig("mammoth", "name"),
        slot_name: config.dig("replication", "slot"),
        publication_name: Array(config.dig("replication", "publications")).join(","),
        max_attempts: config.dig("retry", "max_attempts"),
        retry_schedule: config.dig("retry", "schedule_seconds"),
        sleeper: sleeper
      )
    end

    # Deliver an event with retry, checkpoint, and DLQ handling.
    #
    # @param event [Hash, #to_h] normalized event
    # @return [Hash] delivery summary
    def deliver(event)
      attempts = 0

      begin
        attempts += 1
        result = sink.deliver(event)
        checkpoint(event)
        result.merge(attempts: attempts)
      rescue DeliveryError => e
        return dead_letter(event, e, attempts) if attempts >= max_attempts

        wait_before_retry(attempts)
        retry
      end
    end

    private

    def checkpoint(event)
      payload = EventSerializer.call(event)
      checkpoint_store.write(
        source_name: source_name,
        slot_name: slot_name,
        publication_name: publication_name,
        last_lsn: payload["source_position"]
      )
    end

    def dead_letter(event, error, attempts)
      id = dead_letter_store.write(
        event: event,
        destination_name: sink.name,
        error: error,
        retry_count: attempts
      )
      { status: "dead_lettered", dead_letter_id: id, attempts: attempts }
    end

    def wait_before_retry(attempts)
      wait_seconds = retry_schedule.fetch(attempts - 1, retry_schedule.last)
      sleeper.call(wait_seconds)
    end
  end
end
