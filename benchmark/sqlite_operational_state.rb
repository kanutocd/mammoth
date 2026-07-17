# frozen_string_literal: true

# Benchmark Mammoth's local SQLite operational-state costs. This helps operators
# understand the overhead of checkpoints, delivered-envelope idempotency ledgers,
# duplicate checks, and dead-letter writes as local state grows. Checkpoint
# cadence here is synthetic store load; it does not model the runtime's
# contiguous progress coordinator.

require_relative "support"

require "mammoth"

module MammothBenchmarks
  class SQLiteOperationalStateBenchmark
    attr_reader :records, :dead_letters, :checkpoint_interval

    def initialize(
      records: Helpers.env_integer("MAMMOTH_BENCH_RECORDS", 10_000),
      dead_letters: Helpers.env_integer("MAMMOTH_BENCH_DEAD_LETTERS", 1_000),
      checkpoint_interval: Helpers.env_integer("MAMMOTH_BENCH_CHECKPOINT_INTERVAL", 100)
    )
      @records = records
      @dead_letters = dead_letters
      @checkpoint_interval = checkpoint_interval
    end

    def run
      puts "Mammoth SQLite operational-state benchmark"
      puts "records=#{records} dead_letters=#{dead_letters} checkpoint_interval=#{checkpoint_interval}"
      puts

      result = Helpers.with_temp_sqlite { |db_path| run_once(db_path) }
      print_result(result)
      Helpers.maybe_print_json([result])
      [result]
    end

    private

    def run_once(db_path)
      sqlite = Mammoth::SQLiteStore.connect(db_path).bootstrap!
      checkpoint_store = Mammoth::CheckpointStore.new(sqlite)
      delivered_store = Mammoth::DeliveredEnvelopeStore.new(sqlite)
      dead_letter_store = Mammoth::DeadLetterStore.new(sqlite)

      delivered_elapsed = measure { write_delivered(delivered_store, checkpoint_store) }
      duplicate_elapsed = measure { check_duplicates(delivered_store) }
      dead_letter_elapsed = measure { write_dead_letters(dead_letter_store) }

      {
        records: records,
        dead_letters: dead_letters,
        checkpoint_interval: checkpoint_interval,
        delivered_write_seconds: delivered_elapsed.round(6),
        delivered_writes_per_second: Helpers.rate(records, delivered_elapsed),
        duplicate_check_seconds: duplicate_elapsed.round(6),
        duplicate_checks_per_second: Helpers.rate(records, duplicate_elapsed),
        dead_letter_write_seconds: dead_letter_elapsed.round(6),
        dead_letter_writes_per_second: Helpers.rate(dead_letters, dead_letter_elapsed),
        delivered_envelopes: delivered_store.count,
        dead_letters_total: dead_letter_store.count,
        checkpoints: checkpoint_store.count,
        sqlite_bytes: File.size(db_path)
      }
    end

    def write_delivered(delivered_store, checkpoint_store)
      records.times do |index|
        position = index.to_s
        delivered_store.record!(
          idempotency_key: "benchmark:slot:webhook:transaction:tx-#{index}:#{position}",
          source_name: "benchmark_mammoth",
          slot_name: "benchmark_slot",
          destination_name: "benchmark_webhook",
          delivery_unit: "transaction",
          transaction_id: "tx-#{index}",
          source_position: position
        )
        next unless (index % checkpoint_interval).zero?

        checkpoint_store.write(
          source_name: "benchmark_mammoth",
          slot_name: "benchmark_slot",
          publication_name: "benchmark_publication",
          last_lsn: position
        )
      end
    end

    def check_duplicates(delivered_store)
      records.times do |index|
        delivered_store.delivered?("benchmark:slot:webhook:transaction:tx-#{index}:#{index}")
      end
    end

    def write_dead_letters(dead_letter_store)
      dead_letters.times do |index|
        dead_letter_store.write(
          event: Helpers.build_events(1, prefix: "dead-letter-#{index}", source_position: index.to_s).fetch(0),
          destination_name: "benchmark_webhook",
          error: RuntimeError.new("benchmark failure"),
          retry_count: 3
        )
      end
    end

    def measure
      started_at = Helpers.monotonic_time
      yield
      Helpers.monotonic_time - started_at
    end

    def print_result(result)
      Helpers.print_table(
        %w[records dlq checkpoints db_bytes delivered/sec dup/sec dlq/sec],
        [result]
      ) do |row|
        [
          row.fetch(:records),
          row.fetch(:dead_letters_total),
          row.fetch(:checkpoints),
          row.fetch(:sqlite_bytes),
          row.fetch(:delivered_writes_per_second),
          row.fetch(:duplicate_checks_per_second),
          row.fetch(:dead_letter_writes_per_second)
        ]
      end
    end
  end
end

MammothBenchmarks::SQLiteOperationalStateBenchmark.new.run if $PROGRAM_NAME == __FILE__
