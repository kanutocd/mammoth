# frozen_string_literal: true

# Benchmark destination payload-policy projection independently from HTTP,
# retry, persistence, and source normalization.

require_relative "support"

require "mammoth"

module MammothBenchmarks
  class PayloadPolicyBenchmark
    SCENARIOS = %w[inactive remove mask].freeze

    attr_reader :transformations, :warmup_transformations, :events_per_transaction

    def initialize(
      transformations: Helpers.env_integer("MAMMOTH_BENCH_TRANSFORMATIONS", 100_000),
      warmup_transformations: Helpers.env_integer("MAMMOTH_BENCH_WARMUP_TRANSFORMATIONS", 5_000),
      events_per_transaction: Helpers.env_integer("MAMMOTH_BENCH_EVENTS_PER_TRANSACTION", 4)
    )
      @transformations = transformations
      @warmup_transformations = warmup_transformations
      @events_per_transaction = events_per_transaction
    end

    def run
      validate_configuration!
      payload = canonical_payload
      policies = build_policies
      validate_projection!(payload, policies)

      puts "Mammoth payload policy benchmark"
      puts "transformations=#{transformations} warmup_transformations=#{warmup_transformations} " \
           "events_per_transaction=#{events_per_transaction}"
      puts

      results = SCENARIOS.map { |name| measure(name, payload, policies.fetch(name)) }
      print_results(results)
      Helpers.maybe_print_json(results)
      results
    end

    private

    def canonical_payload
      events = Array.new(events_per_transaction) do |index|
        CDC::Core::ChangeEvent.new(
          operation: :update,
          schema: "public",
          table: "orders",
          old_values: row(index, "old"),
          new_values: row(index, "new"),
          primary_key: { "id" => index + 1, "tenant_token" => "tenant-#{index + 1}" },
          transaction_id: 42,
          commit_lsn: "0/ABC",
          sequence_number: index,
          metadata: { "event_id" => "policy-event-#{index + 1}", "source" => "pgoutput" }
        )
      end
      envelope = CDC::Core::TransactionEnvelope.new(
        transaction_id: 42,
        commit_lsn: "0/ABC",
        committed_at: Time.utc(2026, 7, 19, 12),
        events: events,
        metadata: { "event_id" => "policy-transaction" }
      )
      Mammoth::TransactionEnvelopeSerializer.call(envelope)
    end

    def row(index, version)
      {
        "id" => index + 1,
        "tenant_token" => "tenant-#{index + 1}",
        "customer_email" => "customer-#{index + 1}@example.com",
        "card_token" => "#{version}-token-#{index + 1}",
        "status" => version == "old" ? "pending" : "paid"
      }
    end

    def build_policies
      {
        "inactive" => Mammoth::PayloadPolicy.new,
        "remove" => policy("remove"),
        "mask" => policy("mask")
      }
    end

    def policy(action)
      Mammoth::PayloadPolicy.new(
        "rules" => [
          {
            "tables" => ["orders"],
            "columns" => %w[customer_email card_token tenant_token],
            "action" => action
          }
        ]
      )
    end

    def validate_projection!(payload, policies)
      raise "inactive policy changed canonical payload" unless policies.fetch("inactive").apply(payload).equal?(payload)

      removed = policies.fetch("remove").apply(payload).fetch("events").fetch(0)
      masked = policies.fetch("mask").apply(payload).fetch("events").fetch(0)
      raise "remove policy retained PII" if removed.fetch("data").key?("customer_email")
      raise "mask policy did not replace PII" unless masked.dig("data", "customer_email") == "[REDACTED]"
    end

    def measure(name, payload, policy)
      warmup_transformations.times { policy.apply(payload) }
      GC.start
      allocations_before = GC.stat(:total_allocated_objects)
      started_at = Helpers.monotonic_time
      transformations.times { policy.apply(payload) }
      elapsed = Helpers.monotonic_time - started_at
      allocations = GC.stat(:total_allocated_objects) - allocations_before
      projected = policy.apply(payload)

      {
        scenario: name,
        transformations: transformations,
        events: transformations * events_per_transaction,
        elapsed_seconds: elapsed.round(6),
        transformations_per_second: Helpers.rate(transformations, elapsed),
        events_per_second: Helpers.rate(transformations * events_per_transaction, elapsed),
        microseconds_per_transformation: ((elapsed / transformations) * 1_000_000).round(3),
        allocations_per_transformation: (allocations / transformations.to_f).round(2),
        payload_bytes: JSON.generate(projected).bytesize
      }
    end

    def validate_configuration!
      raise ArgumentError, "MAMMOTH_BENCH_TRANSFORMATIONS must be positive" unless transformations.positive?
      if warmup_transformations.negative?
        raise ArgumentError, "MAMMOTH_BENCH_WARMUP_TRANSFORMATIONS must not be negative"
      end
      return if events_per_transaction.positive?

      raise ArgumentError, "MAMMOTH_BENCH_EVENTS_PER_TRANSACTION must be positive"
    end

    def print_results(results)
      Helpers.print_table(
        %w[scenario transformations events transformations/sec events/sec us/transformation allocs/transformation bytes],
        results
      ) do |row|
        [
          row.fetch(:scenario),
          row.fetch(:transformations),
          row.fetch(:events),
          row.fetch(:transformations_per_second),
          row.fetch(:events_per_second),
          row.fetch(:microseconds_per_transformation),
          row.fetch(:allocations_per_transformation),
          row.fetch(:payload_bytes)
        ]
      end
    end
  end
end

MammothBenchmarks::PayloadPolicyBenchmark.new.run if $PROGRAM_NAME == __FILE__
