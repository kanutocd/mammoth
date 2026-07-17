# frozen_string_literal: true

# Benchmark Mammoth's cdc-concurrent delivery runtime without requiring a live
# PostgreSQL instance. This exercises the same in-process Mammoth delivery
# boundary used after pgoutput-source-adapter creates a TransactionEnvelope:
#
#   TransactionEnvelope -> ConcurrentDeliveryRuntime -> DeliveryProcessor
#                       -> DeliveryWorker -> ProcessorResult -> Observer
#
# It is intentionally not a PostgreSQL logical-replication benchmark. Use this
# to measure downstream concurrent delivery behavior under controlled sink
# latency. It does not benchmark source-adapter transaction normalization or
# multi-destination webhook fanout.

require "json"
require "securerandom"
require "time"
require "cdc/core"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

require "mammoth/errors"
require "mammoth/delivery_processor"
require "mammoth/concurrent_delivery_runtime"

module MammothBenchmarks
  # DeliveryWorker test sink used with exact CDC core work items.
  #
  # Mammoth::DeliveryProcessor calls #deliver_transaction when configured with
  # delivery_unit: :transaction. This fake worker lets the benchmark exercise the
  # real ConcurrentDeliveryRuntime and DeliveryProcessor without doing network IO.
  class SyntheticDeliveryWorker
    attr_reader :latency_seconds, :mutex, :latencies, :delivered_transactions, :delivered_events

    def initialize(latency_seconds:)
      @latency_seconds = latency_seconds
      @mutex = Mutex.new
      @latencies = []
      @delivered_transactions = 0
      @delivered_events = 0
    end

    def deliver_transaction(envelope)
      started_at = monotonic_time
      sleep(latency_seconds) if latency_seconds.positive?
      elapsed = monotonic_time - started_at

      mutex.synchronize do
        latencies << elapsed
        @delivered_transactions += 1
        @delivered_events += envelope.events.length
      end

      {
        ok: true,
        transaction_id: envelope.transaction_id,
        event_count: envelope.events.length,
        latency_seconds: elapsed
      }
    end

    def snapshot
      mutex.synchronize do
        {
          delivered_transactions: delivered_transactions,
          delivered_events: delivered_events,
          latencies: latencies.dup
        }
      end
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  class ConcurrentDeliveryBenchmark
    DEFAULT_CONCURRENCY = [1, 5, 10, 25].freeze

    attr_reader :transactions, :events_per_transaction, :latency_ms, :concurrency_values,
                :preserve_order, :warmup_transactions

    def initialize(
      transactions: env_integer("MAMMOTH_BENCH_TRANSACTIONS", 1_000),
      events_per_transaction: env_integer("MAMMOTH_BENCH_EVENTS_PER_TRANSACTION", 4),
      latency_ms: env_float("MAMMOTH_BENCH_LATENCY_MS", 10.0),
      concurrency_values: env_concurrency_values,
      preserve_order: env_boolean("MAMMOTH_BENCH_PRESERVE_ORDER", false),
      warmup_transactions: env_integer("MAMMOTH_BENCH_WARMUP_TRANSACTIONS", 100)
    )
      @transactions = transactions
      @events_per_transaction = events_per_transaction
      @latency_ms = latency_ms
      @concurrency_values = concurrency_values
      @preserve_order = preserve_order
      @warmup_transactions = warmup_transactions
    end

    def run
      puts "Mammoth concurrent delivery benchmark"
      puts "transactions=#{transactions} events_per_transaction=#{events_per_transaction} " \
           "sink_latency_ms=#{latency_ms} preserve_order=#{preserve_order}"
      puts
      puts format("%12s %12s %12s %12s %12s %12s", "concurrency", "tx/sec", "events/sec", "avg_ms", "p95_ms", "elapsed_s")
      puts "-" * 80

      results = concurrency_values.map { |concurrency| run_once(concurrency) }
      results.each { |result| print_result(result) }

      if ENV["MAMMOTH_BENCH_JSON"]
        puts
        puts JSON.pretty_generate(results)
      end

      results
    end

    private

    def env_integer(name, default)
      self.class.env_integer(name, default)
    end

    def env_float(name, default)
      self.class.env_float(name, default)
    end

    def env_boolean(name, default)
      self.class.env_boolean(name, default)
    end

    def env_concurrency_values
      self.class.env_concurrency_values
    end

    def self.env_integer(name, default)
      value = ENV[name]
      return default if value.nil? || value.empty?

      Integer(value, 10)
    end

    def self.env_float(name, default)
      value = ENV[name]
      return default if value.nil? || value.empty?

      Float(value)
    end

    def self.env_boolean(name, default)
      value = ENV[name]
      return default if value.nil? || value.empty?

      %w[1 true yes on].include?(value.downcase)
    end

    def self.env_concurrency_values
      value = ENV["MAMMOTH_BENCH_CONCURRENCY"]
      return DEFAULT_CONCURRENCY if value.nil? || value.empty?

      value.split(",").map { |entry| Integer(entry.strip, 10) }
    end

    def run_once(concurrency)
      worker = SyntheticDeliveryWorker.new(latency_seconds: latency_ms / 1_000.0)
      processor = Mammoth::DeliveryProcessor.new(delivery_worker: worker, delivery_unit: :transaction)
      runtime = Mammoth::ConcurrentDeliveryRuntime.new(
        processor: processor,
        concurrency: concurrency,
        timeout: nil,
        preserve_order: preserve_order
      )

      runtime.process_many(build_envelopes(warmup_transactions, prefix: "warmup")) if warmup_transactions.positive?

      benchmark_worker = SyntheticDeliveryWorker.new(latency_seconds: latency_ms / 1_000.0)
      benchmark_processor = Mammoth::DeliveryProcessor.new(delivery_worker: benchmark_worker, delivery_unit: :transaction)
      benchmark_runtime = Mammoth::ConcurrentDeliveryRuntime.new(
        processor: benchmark_processor,
        concurrency: concurrency,
        timeout: nil,
        preserve_order: preserve_order
      )

      items = build_envelopes(transactions, prefix: "run")
      started_at = monotonic_time
      benchmark_runtime.process_many(items)
      elapsed = monotonic_time - started_at
      snapshot = benchmark_worker.snapshot

      runtime.shutdown
      benchmark_runtime.shutdown

      build_result(concurrency, elapsed, snapshot)
    end

    def build_result(concurrency, elapsed, snapshot)
      delivered_transactions = snapshot.fetch(:delivered_transactions)
      delivered_events = snapshot.fetch(:delivered_events)
      latencies = snapshot.fetch(:latencies)

      {
        concurrency: concurrency,
        preserve_order: preserve_order,
        transactions: delivered_transactions,
        events: delivered_events,
        sink_latency_ms: latency_ms,
        elapsed_seconds: elapsed.round(6),
        transactions_per_second: rate(delivered_transactions, elapsed),
        events_per_second: rate(delivered_events, elapsed),
        average_latency_ms: (average(latencies) * 1_000).round(3),
        p95_latency_ms: (percentile(latencies, 0.95) * 1_000).round(3)
      }
    end

    def print_result(result)
      puts format(
        "%12d %12.2f %12.2f %12.3f %12.3f %12.3f",
        result.fetch(:concurrency),
        result.fetch(:transactions_per_second),
        result.fetch(:events_per_second),
        result.fetch(:average_latency_ms),
        result.fetch(:p95_latency_ms),
        result.fetch(:elapsed_seconds)
      )
    end

    def build_envelopes(count, prefix:)
      Array.new(count) do |index|
        position = 10_000 + index
        events = Array.new(events_per_transaction) do |event_index|
          CDC::Core::ChangeEvent.new(
            operation: event_index.zero? ? "insert" : "update",
            schema: "public",
            table: "orders",
            primary_key: { "id" => index + 1 },
            new_values: { "id" => index + 1 },
            commit_lsn: position,
            metadata: { "benchmark" => true, "event_index" => event_index }
          )
        end

        CDC::Core::TransactionEnvelope.new(
          transaction_id: "#{prefix}-#{index + 1}",
          commit_lsn: position,
          committed_at: Time.now.utc,
          events: events,
          metadata: { "benchmark" => true, "event_id" => SecureRandom.uuid }
        )
      end
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def rate(count, elapsed)
      return 0.0 if elapsed.zero?

      (count / elapsed).round(2)
    end

    def average(values)
      return 0.0 if values.empty?

      values.sum / values.length.to_f
    end

    def percentile(values, quantile)
      return 0.0 if values.empty?

      sorted = values.sort
      index = [(sorted.length * quantile).ceil - 1, 0].max
      sorted.fetch(index)
    end
  end
end

MammothBenchmarks::ConcurrentDeliveryBenchmark.new.run if $PROGRAM_NAME == __FILE__
