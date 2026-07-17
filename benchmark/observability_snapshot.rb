# frozen_string_literal: true

# Benchmark Mammoth::ObservabilitySnapshot over different local SQLite state
# sizes. This helps operators understand local /readyz and /metrics formatting
# cost as delivered ledgers and dead-letter tables grow. Live PostgreSQL slot
# inspection latency is intentionally excluded.

require_relative "support"

require "mammoth"

module MammothBenchmarks
  class ObservabilitySnapshotBenchmark
    attr_reader :delivered, :dead_letters, :snapshots

    def initialize(
      delivered: Helpers.env_integer("MAMMOTH_BENCH_DELIVERED", 10_000),
      dead_letters: Helpers.env_integer("MAMMOTH_BENCH_DEAD_LETTERS", 1_000),
      snapshots: Helpers.env_integer("MAMMOTH_BENCH_SNAPSHOTS", 100)
    )
      @delivered = delivered
      @dead_letters = dead_letters
      @snapshots = snapshots
    end

    def run
      puts "Mammoth observability snapshot benchmark"
      puts "delivered=#{delivered} dead_letters=#{dead_letters} snapshots=#{snapshots}"
      puts

      result = Helpers.with_temp_sqlite { |db_path| run_once(db_path) }
      print_result(result)
      Helpers.maybe_print_json([result])
      [result]
    end

    private

    def run_once(db_path)
      adapter = Mammoth::OperationalState::SQLiteAdapter.new(Mammoth::SQLiteStore.connect(db_path))
      adapter.bootstrap!
      seed_state(adapter)
      snapshot = Mammoth::ObservabilitySnapshot.new(
        config(db_path),
        state_adapter: adapter,
        dispatch_metrics: build_dispatch_metrics
      )

      readiness_elapsed = measure { snapshots.times { snapshot.readiness } }
      metrics_elapsed = measure { snapshots.times { snapshot.prometheus } }

      {
        delivered: delivered,
        dead_letters: dead_letters,
        snapshots: snapshots,
        readiness_seconds: readiness_elapsed.round(6),
        readiness_per_second: Helpers.rate(snapshots, readiness_elapsed),
        metrics_seconds: metrics_elapsed.round(6),
        metrics_per_second: Helpers.rate(snapshots, metrics_elapsed),
        sqlite_bytes: File.size(db_path)
      }
    end

    def seed_state(adapter)
      adapter.checkpoint_store.write(
        source_name: "benchmark_mammoth",
        slot_name: "benchmark_slot",
        publication_name: "benchmark_publication",
        last_lsn: "0"
      )
      delivered.times { |index| write_delivered(adapter.delivered_envelope_store, index) }
      dead_letters.times { |index| write_dead_letter(adapter.dead_letter_store, index) }
    end

    def build_dispatch_metrics
      Mammoth::DispatchMetrics.new.tap do |metrics|
        metrics.increment(
          CDC::Core::Observer.started_metric_name,
          "kind" => "transaction_envelope", "size" => 4
        )
        metrics.increment(
          CDC::Core::Observer.succeeded_metric_name,
          "kind" => "processor_result", "status" => "success", "retryable" => false
        )
      end
    end

    def write_delivered(store, index)
      store.record!(
        idempotency_key: "benchmark:slot:webhook:transaction:tx-#{index}:#{index}",
        source_name: "benchmark_mammoth",
        slot_name: "benchmark_slot",
        destination_name: "benchmark_webhook",
        delivery_unit: "transaction",
        transaction_id: "tx-#{index}",
        source_position: index.to_s
      )
    end

    def write_dead_letter(store, index)
      store.write(
        event: Helpers.build_events(1, prefix: "dead-letter-#{index}", source_position: index.to_s).fetch(0),
        destination_name: "benchmark_webhook",
        error: RuntimeError.new("benchmark failure"),
        retry_count: 3
      )
    end

    def config(db_path)
      Struct.new(:path) do
        def data
          { "webhook" => { "name" => "benchmark_webhook" } }
        end

        def dig(*keys)
          {
            %w[mammoth name] => "benchmark_mammoth",
            %w[sqlite path] => path
          }.fetch(keys, nil)
        end
      end.new(db_path)
    end

    def measure
      started_at = Helpers.monotonic_time
      yield
      Helpers.monotonic_time - started_at
    end

    def print_result(result)
      Helpers.print_table(
        %w[delivered dlq snapshots db_bytes ready/sec metrics/sec],
        [result]
      ) do |row|
        [
          row.fetch(:delivered),
          row.fetch(:dead_letters),
          row.fetch(:snapshots),
          row.fetch(:sqlite_bytes),
          row.fetch(:readiness_per_second),
          row.fetch(:metrics_per_second)
        ]
      end
    end
  end
end

MammothBenchmarks::ObservabilitySnapshotBenchmark.new.run if $PROGRAM_NAME == __FILE__
