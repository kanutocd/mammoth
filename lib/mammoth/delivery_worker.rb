# frozen_string_literal: true

module Mammoth
  # Delivers normalized events with retry, ledger, and dead-letter handling.
  #
  # DeliveryWorker is Mammoth's first reliable delivery unit. It intentionally keeps
  # the delivery contract small: attempt webhook delivery, record idempotent
  # success, and persist exhausted failures to the dead letter queue. Contiguous
  # checkpointing is owned by DeliveryProgressCoordinator.
  class DeliveryWorker
    # Default source name used when an event does not provide one.
    DEFAULT_SOURCE = "postgresql"

    attr_reader :sink, :checkpoint_store, :dead_letter_store, :delivered_envelope_store, :retry_schedule, :max_attempts,
                :sleeper, :source_name, :slot_name, :publication_name, :route_filter, :payload_policy, :enabled

    # @param sink [#deliver] destination sink
    # @param checkpoint_store [Mammoth::CheckpointStore] retained dependency; shared progress owns writes
    # @param dead_letter_store [Mammoth::DeadLetterStore] dead letter persistence
    # @param delivered_envelope_store [Mammoth::DeliveredEnvelopeStore] downstream delivery ledger
    # @param source_name [String] logical source name
    # @param slot_name [String] replication slot name
    # @param publication_name [String] publication name
    # @param max_attempts [Integer] maximum delivery attempts
    # @param retry_schedule [Array<Integer>] retry wait schedule in seconds
    # @param sleeper [#call] sleep strategy, injectable for tests
    # @param route_filter [Mammoth::RouteFilter, nil] optional destination route matcher
    # @param payload_policy [Mammoth::PayloadPolicy, nil] destination payload transformation policy
    # @param enabled [Boolean] whether this destination accepts new deliveries
    def initialize(sink:, checkpoint_store:, dead_letter_store:, delivered_envelope_store:, source_name:, slot_name:,
                   publication_name:, max_attempts:, retry_schedule:, sleeper: Kernel.method(:sleep),
                   route_filter: nil, payload_policy: nil, enabled: true)
      @sink = sink
      @checkpoint_store = checkpoint_store
      @dead_letter_store = dead_letter_store
      @delivered_envelope_store = delivered_envelope_store
      @source_name = source_name
      @slot_name = slot_name
      @publication_name = publication_name
      @max_attempts = max_attempts
      @retry_schedule = retry_schedule
      @sleeper = sleeper
      @route_filter = route_filter || RouteFilter.new
      @payload_policy = payload_policy || PayloadPolicy.new
      @enabled = enabled
      return unless @payload_policy.active? && !sink.respond_to?(:deliver_payload)

      raise ConfigurationError, "destination #{destination_name} does not accept prepared payloads"
    end

    # Build a delivery worker from Mammoth configuration and stores.
    #
    # @param config [Mammoth::Configuration] loaded configuration
    # @param sink [#deliver] destination sink
    # @param checkpoint_store [Mammoth::CheckpointStore] retained dependency; shared progress owns writes
    # @param dead_letter_store [Mammoth::DeadLetterStore] dead letter persistence
    # @param delivered_envelope_store [Mammoth::DeliveredEnvelopeStore] downstream delivery ledger
    # @param sleeper [#call] sleep strategy
    # @return [Mammoth::DeliveryWorker]
    def self.from_config(config, sink:, checkpoint_store:, dead_letter_store:, delivered_envelope_store:,
                         sleeper: Kernel.method(:sleep), delivery_policy: {})
      new(
        sink: sink,
        checkpoint_store: checkpoint_store,
        dead_letter_store: dead_letter_store,
        delivered_envelope_store: delivered_envelope_store,
        source_name: config.dig("mammoth", "name"),
        slot_name: config.dig("replication", "slot"),
        publication_name: Array(config.dig("replication", "publications")).join(","),
        max_attempts: delivery_policy.fetch("max_attempts", config.dig("retry", "max_attempts")),
        retry_schedule: delivery_policy.fetch("schedule_seconds", config.dig("retry", "schedule_seconds")),
        sleeper: sleeper,
        route_filter: delivery_policy.fetch("route_filter", RouteFilter.new),
        payload_policy: delivery_policy.fetch("payload_policy", PayloadPolicy.new),
        enabled: delivery_policy.fetch("enabled", true)
      )
    end

    # Deliver a transaction envelope with retry, ledger, and DLQ handling.
    #
    # @param envelope [CDC::Core::TransactionEnvelope] CDC transaction envelope
    # @return [Hash] delivery summary
    def deliver_transaction(envelope)
      deliver_work(envelope, serializer: TransactionEnvelopeSerializer, delivery_method: :deliver_transaction)
    end

    # Deliver an event with retry, ledger, and DLQ handling.
    #
    # @param event [CDC::Core::ChangeEvent] normalized event
    # @return [Hash] delivery summary
    def deliver(event)
      deliver_work(event, serializer: EventSerializer, delivery_method: :deliver)
    end

    # Replay one exact destination payload without reapplying the current policy.
    #
    # @param payload [Hash] prepared payload persisted in the dead-letter store
    # @return [Hash] delivery summary
    def deliver_payload(payload)
      prepared = PreparedDelivery.from_payload(payload)
      delivery_method = transaction_payload?(payload) ? :deliver_transaction : :deliver
      deliver_prepared(prepared, work: nil, delivery_method: delivery_method)
    end

    private

    def deliver_work(work, serializer:, delivery_method:)
      prepared = PreparedDelivery.build(work, serializer: serializer, payload_policy: payload_policy)
      deliver_prepared(prepared, work: work, delivery_method: delivery_method)
    end

    # rubocop:disable Metrics/MethodLength
    def deliver_prepared(prepared, work:, delivery_method:)
      attempts = 0
      canonical_payload = prepared.canonical_payload
      payload = prepared.payload
      delivery_unit = delivery_unit_for(delivery_method)
      idempotency_key = idempotency_key_for(payload: canonical_payload, delivery_unit: delivery_unit)

      skip_result = skip_result_for(canonical_payload, idempotency_key: idempotency_key)
      return skip_result if skip_result

      if delivered_envelope_store.delivered?(idempotency_key)
        return {
          status: "skipped",
          duplicate: true,
          idempotency_key: idempotency_key,
          attempts: attempts,
          destination: destination_name
        }
      end

      begin
        attempts += 1
        result = deliver_to_sink(prepared, work: work, delivery_method: delivery_method)
        delivered_envelope_store.record!(
          idempotency_key: idempotency_key,
          source_name: source_name,
          slot_name: slot_name,
          destination_name: destination_name,
          delivery_unit: delivery_unit.to_s,
          transaction_id: payload["transaction_id"],
          source_position: payload["source_position"]
        )
        result.merge(attempts: attempts, idempotency_key: idempotency_key)
      rescue DeliveryError => e
        return dead_letter(payload, e, attempts) if attempts >= max_attempts

        wait_before_retry(attempts)
        retry
      end
    end
    # rubocop:enable Metrics/MethodLength

    def idempotency_key_for(payload:, delivery_unit:)
      [
        source_name,
        slot_name,
        destination_name,
        delivery_unit,
        payload["transaction_id"] || payload["event_id"],
        payload["source_position"]
      ].compact.join(":")
    end

    def delivery_unit_for(delivery_method)
      delivery_method == :deliver_transaction ? :transaction : :event
    end

    def destination_name
      sink.respond_to?(:name) ? sink.name : sink.class.name
    end

    def skip_result_for(payload, idempotency_key:)
      return skipped(payload, idempotency_key:, reason: "disabled") unless enabled

      skipped(payload, idempotency_key:, reason: "route_mismatch") unless route_filter.match_payload?(payload)
    end

    def skipped(_payload, idempotency_key:, reason:)
      {
        status: "skipped",
        reason: reason,
        duplicate: false,
        idempotency_key: idempotency_key,
        attempts: 0,
        destination: destination_name
      }
    end

    def wait_before_retry(attempts)
      wait_seconds = retry_schedule.fetch(attempts - 1, retry_schedule.last)
      sleeper.call(wait_seconds)
    end

    def deliver_to_sink(prepared, work:, delivery_method:)
      return sink.deliver_payload(prepared.payload) if sink.respond_to?(:deliver_payload)
      return sink.public_send(delivery_method, work) if work && !payload_policy.active?

      raise ConfigurationError, "destination #{destination_name} does not accept prepared payloads"
    end

    def dead_letter(payload, error, attempts)
      id = dead_letter_store.write_payload(
        payload: payload,
        destination_name: sink.name,
        error: error,
        retry_count: attempts
      )
      { status: "dead_lettered", dead_letter_id: id, attempts: attempts }
    end

    def transaction_payload?(payload)
      payload["type"] == TransactionEnvelopeSerializer::PAYLOAD_TYPE
    end
  end
end
