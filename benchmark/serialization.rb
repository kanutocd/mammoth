# frozen_string_literal: true

# Benchmark Mammoth's event and transaction payload projection without network
# or persistence overhead. The scenarios compare metadata-supplied IDs with the
# deterministic SHA-256 fallback-ID path used when upstream IDs are absent.

require_relative "support"

require "mammoth/event_serializer"
require "mammoth/transaction_envelope_serializer"

module MammothBenchmarks
  # Compares Mammoth payload projection with explicit and generated IDs.
  class SerializationBenchmark
    SCENARIOS = %w[
      event_explicit_id
      event_fallback_id
      transaction_explicit_ids
      transaction_fallback_ids
    ].freeze

    attr_reader :serializations, :warmup_serializations, :events_per_transaction

    def initialize(
      serializations: Helpers.env_integer("MAMMOTH_BENCH_SERIALIZATIONS", 100_000),
      warmup_serializations: Helpers.env_integer("MAMMOTH_BENCH_WARMUP_SERIALIZATIONS", 5_000),
      events_per_transaction: Helpers.env_integer("MAMMOTH_BENCH_EVENTS_PER_TRANSACTION", 4)
    )
      @serializations = serializations
      @warmup_serializations = warmup_serializations
      @events_per_transaction = events_per_transaction
    end

    def run
      validate_configuration!
      workloads = build_workloads
      fallback_workload = workloads.fetch("transaction_fallback_ids")
      validate_fallback_identity!(fallback_workload.call, fallback_workload.call)

      puts "Mammoth serialization benchmark"
      puts "serializations=#{serializations} warmup_serializations=#{warmup_serializations} " \
           "events_per_transaction=#{events_per_transaction}"
      puts

      results = SCENARIOS.map { |name| measure(name, workloads.fetch(name)) }
      print_results(results)
      Helpers.maybe_print_json(results)
      results
    end

    private

    def build_workloads
      explicit_event = build_event(sequence_number: 0, explicit_id: true)
      fallback_event = build_event(sequence_number: 0, explicit_id: false)
      explicit_envelope = build_envelope(explicit_ids: true)
      fallback_envelope = build_envelope(explicit_ids: false)

      {
        "event_explicit_id" => -> { Mammoth::EventSerializer.call(explicit_event) },
        "event_fallback_id" => -> { Mammoth::EventSerializer.call(fallback_event) },
        "transaction_explicit_ids" => -> { Mammoth::TransactionEnvelopeSerializer.call(explicit_envelope) },
        "transaction_fallback_ids" => -> { Mammoth::TransactionEnvelopeSerializer.call(fallback_envelope) }
      }
    end

    def build_envelope(explicit_ids:)
      events = Array.new(events_per_transaction) do |sequence_number|
        build_event(sequence_number: sequence_number, explicit_id: explicit_ids)
      end
      metadata = { "benchmark" => true }
      metadata["event_id"] = "benchmark-transaction" if explicit_ids

      CDC::Core::TransactionEnvelope.new(
        transaction_id: 42,
        commit_lsn: "0/ABC",
        committed_at: Time.utc(2026, 7, 19, 12),
        events: events,
        metadata: metadata
      )
    end

    def build_event(sequence_number:, explicit_id:)
      metadata = { "benchmark" => true, "source" => "pgoutput" }
      metadata["event_id"] = "benchmark-event-#{sequence_number}" if explicit_id

      CDC::Core::ChangeEvent.new(
        operation: :update,
        schema: "public",
        table: "orders",
        old_values: { "id" => 4, "status" => "pending", "total_cents" => 4999 },
        new_values: { "id" => 4, "status" => "paid", "total_cents" => 4999 },
        primary_key: { "id" => 4 },
        transaction_id: 42,
        commit_lsn: "0/ABC",
        sequence_number: sequence_number,
        occurred_at: Time.utc(2026, 7, 19, 12),
        metadata: metadata
      )
    end

    def measure(name, workload) # rubocop:disable Metrics/AbcSize
      warmup_serializations.times { workload.call }
      GC.start
      allocations_before = GC.stat(:total_allocated_objects)
      started_at = Helpers.monotonic_time
      serializations.times { workload.call }
      elapsed = Helpers.monotonic_time - started_at
      allocations = GC.stat(:total_allocated_objects) - allocations_before
      payload = workload.call
      items_per_operation = name.start_with?("transaction_") ? events_per_transaction : 1

      {
        scenario: name,
        operations: serializations,
        events: serializations * items_per_operation,
        elapsed_seconds: elapsed.round(6),
        operations_per_second: Helpers.rate(serializations, elapsed),
        events_per_second: Helpers.rate(serializations * items_per_operation, elapsed),
        microseconds_per_operation: ((elapsed / serializations) * 1_000_000).round(3),
        allocations_per_operation: (allocations / serializations.to_f).round(2),
        payload_bytes: JSON.generate(payload).bytesize
      }
    end

    def validate_configuration!
      raise ArgumentError, "MAMMOTH_BENCH_SERIALIZATIONS must be positive" unless serializations.positive?
      raise ArgumentError, "MAMMOTH_BENCH_WARMUP_SERIALIZATIONS must not be negative" if warmup_serializations.negative?
      raise ArgumentError, "MAMMOTH_BENCH_EVENTS_PER_TRANSACTION must be positive" unless events_per_transaction.positive?
    end

    def validate_fallback_identity!(payload, replay_payload)
      event_ids = payload.fetch("events").map { |event| event.fetch("event_id") }
      replay_event_ids = replay_payload.fetch("events").map { |event| event.fetch("event_id") }
      unless event_ids.uniq.length == events_per_transaction
        raise "fallback event IDs collided; benchmark result would be invalid"
      end
      return if event_ids == replay_event_ids && payload.fetch("event_id") == replay_payload.fetch("event_id")

      raise "fallback event IDs changed on replay; benchmark result would be invalid"
    end

    def print_results(results)
      Helpers.print_table(
        %w[scenario operations events ops/sec events/sec us/op allocs/op bytes],
        results
      ) do |row|
        [
          row.fetch(:scenario),
          row.fetch(:operations),
          row.fetch(:events),
          row.fetch(:operations_per_second),
          row.fetch(:events_per_second),
          row.fetch(:microseconds_per_operation),
          row.fetch(:allocations_per_operation),
          row.fetch(:payload_bytes)
        ]
      end
    end
  end
end

MammothBenchmarks::SerializationBenchmark.new.run if $PROGRAM_NAME == __FILE__
