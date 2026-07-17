# frozen_string_literal: true

# Benchmark Mammoth's multi-destination webhook fanout against local
# WEBrick receivers. This covers FanoutDeliveryWorker, per-destination
# DeliveryWorker state, delivered-envelope ledger writes, and real WebhookSink
# HTTP delivery.

require_relative "support"

require "mammoth"

module MammothBenchmarks
  class WebhookFanoutBenchmark
    DEFAULT_DESTINATIONS = [1, 2, 5, 10].freeze

    attr_reader :transactions, :events_per_transaction, :latency_ms, :destination_counts

    def initialize(
      transactions: Helpers.env_integer("MAMMOTH_BENCH_TRANSACTIONS", 250),
      events_per_transaction: Helpers.env_integer("MAMMOTH_BENCH_EVENTS_PER_TRANSACTION", 4),
      latency_ms: Helpers.env_float("MAMMOTH_BENCH_LATENCY_MS", 0.0),
      destination_counts: Helpers.env_list("MAMMOTH_BENCH_DESTINATIONS", DEFAULT_DESTINATIONS,
                                           coercer: ->(entry) { Integer(entry, 10) })
    )
      @transactions = transactions
      @events_per_transaction = events_per_transaction
      @latency_ms = latency_ms
      @destination_counts = destination_counts
    end

    def run
      puts "Mammoth webhook fanout benchmark"
      puts "transactions=#{transactions} events_per_transaction=#{events_per_transaction} " \
           "receiver_latency_ms=#{latency_ms} destinations=#{destination_counts.join(",")}"
      puts

      results = destination_counts.map { |destination_count| run_once(destination_count) }
      print_results(results)
      Helpers.maybe_print_json(results)
      results
    end

    private

    def run_once(destination_count)
      with_receivers(destination_count) do |urls, counters|
        Helpers.with_temp_sqlite do |db_path|
          state_adapter = Mammoth::OperationalState::SQLiteAdapter.new(Mammoth::SQLiteStore.connect(db_path))
          worker = build_fanout_worker(state_adapter, urls)
          envelopes = Helpers.build_envelopes(transactions, events_per_transaction: events_per_transaction)
          started_at = Helpers.monotonic_time
          envelopes.each { |envelope| worker.deliver_transaction(envelope) }
          elapsed = Helpers.monotonic_time - started_at

          build_result(destination_count, elapsed, counters, state_adapter)
        end
      end
    end

    def with_receivers(count)
      receivers = Array.new(count) { LocalHTTPReceiver.new(latency_seconds: latency_ms / 1_000.0) }
      urls = receivers.each_with_index.map { |receiver, index| "#{receiver.url}?destination=#{index + 1}" }

      yield urls, receivers
    ensure
      receivers&.each(&:shutdown)
    end

    def build_fanout_worker(state_adapter, urls)
      workers = urls.each_with_index.map do |url, index|
        Mammoth::DeliveryWorker.new(
          sink: Mammoth::WebhookSink.new(name: "webhook_#{index + 1}", url: url, timeout_seconds: 5),
          checkpoint_store: state_adapter.checkpoint_store,
          dead_letter_store: state_adapter.dead_letter_store,
          delivered_envelope_store: state_adapter.delivered_envelope_store,
          source_name: "benchmark_mammoth",
          slot_name: "benchmark_slot",
          publication_name: "benchmark_publication",
          max_attempts: 1,
          retry_schedule: [1],
          sleeper: ->(_seconds) {}
        )
      end
      Mammoth::FanoutDeliveryWorker.new(workers)
    end

    def build_result(destination_count, elapsed, counters, state_adapter)
      snapshots = counters.map(&:snapshot)
      request_count = snapshots.sum { |counter| counter.fetch(:requests) }
      byte_count = snapshots.sum { |counter| counter.fetch(:bytes) }
      {
        destinations: destination_count,
        transactions: transactions,
        events: transactions * events_per_transaction,
        webhook_requests: request_count,
        delivered_envelopes: state_adapter.delivered_envelope_store.count,
        dead_letters: state_adapter.dead_letter_store.count,
        receiver_latency_ms: latency_ms,
        elapsed_seconds: elapsed.round(6),
        transactions_per_second: Helpers.rate(transactions, elapsed),
        webhook_requests_per_second: Helpers.rate(request_count, elapsed),
        bytes: byte_count
      }
    end

    def print_results(results)
      Helpers.print_table(
        %w[dest tx requests delivered dlq latency_ms tx/sec req/sec elapsed_s],
        results
      ) do |row|
        [
          row.fetch(:destinations),
          row.fetch(:transactions),
          row.fetch(:webhook_requests),
          row.fetch(:delivered_envelopes),
          row.fetch(:dead_letters),
          row.fetch(:receiver_latency_ms),
          row.fetch(:transactions_per_second),
          row.fetch(:webhook_requests_per_second),
          row.fetch(:elapsed_seconds)
        ]
      end
    end
  end
end

MammothBenchmarks::WebhookFanoutBenchmark.new.run if $PROGRAM_NAME == __FILE__
