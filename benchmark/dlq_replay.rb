# frozen_string_literal: true

# Benchmark dead-letter replay mechanics without network IO. This covers SQLite
# pending-row reads, JSON payload parsing, targeted destination replay, delivered
# ledger writes, and resolving successful rows.

require_relative "support"

require "mammoth"

module MammothBenchmarks
  class DLQReplayBenchmark
    attr_reader :dead_letters, :destinations, :delivery_unit

    def initialize(
      dead_letters: Helpers.env_integer("MAMMOTH_BENCH_DEAD_LETTERS", 1_000),
      destinations: Helpers.env_integer("MAMMOTH_BENCH_DESTINATIONS", 2),
      delivery_unit: ENV.fetch("MAMMOTH_BENCH_DELIVERY_UNIT", "transaction")
    )
      @dead_letters = dead_letters
      @destinations = destinations
      @delivery_unit = delivery_unit
    end

    def run
      puts "Mammoth DLQ replay benchmark"
      puts "dead_letters=#{dead_letters} destinations=#{destinations} delivery_unit=#{delivery_unit}"
      puts

      result = Helpers.with_temp_sqlite { |db_path| run_once(db_path) }
      print_result(result)
      Helpers.maybe_print_json([result])
      [result]
    end

    private

    def run_once(db_path)
      state_adapter = Mammoth::OperationalState::SQLiteAdapter.new(Mammoth::SQLiteStore.connect(db_path))
      dead_letter_store = state_adapter.dead_letter_store
      seed_dead_letters(dead_letter_store)
      worker = build_worker(state_adapter)
      rows = dead_letter_store.pending(limit: dead_letters)

      started_at = Helpers.monotonic_time
      rows.each do |row|
        result = replay_row(worker, row)
        dead_letter_store.resolve(row.fetch("id")) unless result.fetch(:status) == "dead_lettered"
      end
      elapsed = Helpers.monotonic_time - started_at

      {
        dead_letters: dead_letters,
        destinations: destinations,
        delivery_unit: delivery_unit,
        elapsed_seconds: elapsed.round(6),
        replayed_per_second: Helpers.rate(dead_letters, elapsed),
        pending: dead_letter_store.count(status: "pending"),
        resolved: dead_letter_store.count(status: "resolved"),
        delivered_envelopes: state_adapter.delivered_envelope_store.count,
        sqlite_bytes: File.size(db_path)
      }
    end

    def seed_dead_letters(store)
      dead_letters.times do |index|
        store.write(
          event: dead_letter_payload(index),
          destination_name: "webhook_#{(index % destinations) + 1}",
          error: RuntimeError.new("benchmark failure"),
          retry_count: 3,
          serializer: serializer
        )
      end
    end

    def dead_letter_payload(index)
      return Helpers.build_events(1, prefix: "event-#{index}", source_position: index.to_s).fetch(0) if delivery_unit == "event"

      Helpers.build_envelopes(1, events_per_transaction: events_per_transaction, prefix: "tx-#{index}").fetch(0)
    end

    def events_per_transaction
      Helpers.env_integer("MAMMOTH_BENCH_EVENTS_PER_TRANSACTION", 4)
    end

    def serializer
      delivery_unit == "event" ? Mammoth::EventSerializer : Mammoth::TransactionEnvelopeSerializer
    end

    def build_worker(state_adapter)
      workers = destinations.times.map do |index|
        Mammoth::DeliveryWorker.new(
          sink: RecordingSink.new("webhook_#{index + 1}"),
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
      workers.one? ? workers.fetch(0) : Mammoth::FanoutDeliveryWorker.new(workers)
    end

    def replay_row(worker, row)
      payload = JSON.parse(row.fetch("payload_json"))
      destination_name = row.fetch("destination_name")
      if payload.fetch("type", nil) == Mammoth::TransactionEnvelopeSerializer::PAYLOAD_TYPE
        envelope = Mammoth::PersistedPayloadDeserializer.transaction(payload)
        worker.respond_to?(:deliver_transaction_to) ? worker.deliver_transaction_to(destination_name, envelope) : worker.deliver_transaction(envelope)
      elsif worker.respond_to?(:deliver_to)
        worker.deliver_to(destination_name, Mammoth::PersistedPayloadDeserializer.event(payload))
      else
        worker.deliver(Mammoth::PersistedPayloadDeserializer.event(payload))
      end
    end

    class RecordingSink
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def deliver(event)
        { event_id: Mammoth::EventSerializer.call(event).fetch("event_id"), destination: name, status: "delivered",
          http_status: 200 }
      end

      def deliver_transaction(envelope)
        { event_id: "transaction-#{envelope.transaction_id}", destination: name, status: "delivered", http_status: 200 }
      end
    end

    def print_result(result)
      Helpers.print_table(
        %w[dlq destinations unit replay/sec pending resolved delivered db_bytes],
        [result]
      ) do |row|
        [
          row.fetch(:dead_letters),
          row.fetch(:destinations),
          row.fetch(:delivery_unit),
          row.fetch(:replayed_per_second),
          row.fetch(:pending),
          row.fetch(:resolved),
          row.fetch(:delivered_envelopes),
          row.fetch(:sqlite_bytes)
        ]
      end
    end
  end
end

MammothBenchmarks::DLQReplayBenchmark.new.run if $PROGRAM_NAME == __FILE__
