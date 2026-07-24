# frozen_string_literal: true

require "test_helper"
require "stringio"

module Mammoth
  # rubocop:disable Metrics/ClassLength
  class DeliveryWorkerTest < Minitest::Test
    def test_delivers_without_advancing_shared_progress
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        worker = build_worker(sqlite, sink: RecordingSink.new)

        result = worker.deliver(sample_event)
        assert_equal "delivered", result.fetch(:status)
        assert_equal 1, result.fetch(:attempts)
        assert_equal 0, CheckpointStore.new(sqlite).count
        assert_equal 0, DeadLetterStore.new(sqlite).count
      end
    end

    def test_retries_before_success # rubocop:disable Metrics/AbcSize
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = FlakySink.new(failures_before_success: 1)
        sleeps = []
        output = StringIO.new
        logger = Logging::Logger.new(level: "info", output:)
        worker = build_worker(sqlite, sink: sink, sleeper: ->(seconds) { sleeps << seconds }, logger:)

        result = worker.deliver(sample_event)
        records = output.string.lines.map { |line| JSON.parse(line) }

        assert_equal "delivered", result.fetch(:status)
        assert_equal 2, result.fetch(:attempts)
        assert_equal [1], sleeps
        assert_equal 0, DeadLetterStore.new(sqlite).count
        assert_equal(%w[delivery_retry delivery_succeeded], records.map { |record| record.fetch("event") })
        assert_equal(%w[warn info], records.map { |record| record.fetch("severity") })
      end
    end

    def test_dead_letters_after_retry_exhaustion
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        worker = build_worker(sqlite, sink: FailingSink.new, sleeper: ->(_seconds) {})

        result = worker.deliver(sample_event)
        dlq = DeadLetterStore.new(sqlite)

        assert_equal "dead_lettered", result.fetch(:status)
        assert_equal 3, result.fetch(:attempts)
        assert_equal 1, dlq.count(status: "pending")
        assert_equal 0, CheckpointStore.new(sqlite).count
      end
    end

    def test_reuses_last_retry_delay_when_attempts_exceed_schedule
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sleeps = []
        worker = DeliveryWorker.new(
          sink: FailingSink.new,
          checkpoint_store: CheckpointStore.new(sqlite),
          dead_letter_store: DeadLetterStore.new(sqlite),
          delivered_envelope_store: DeliveredEnvelopeStore.new(sqlite),
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          max_attempts: 4,
          retry_schedule: [2],
          sleeper: ->(seconds) { sleeps << seconds }
        )

        result = worker.deliver(sample_event)

        assert_equal "dead_lettered", result.fetch(:status)
        assert_equal [2, 2, 2], sleeps
      end
    end

    def test_disabled_destination_skips_without_advancing_shared_progress
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = RecordingSink.new
        worker = build_worker(sqlite, sink: sink, enabled: false)

        result = worker.deliver(sample_event)
        assert_equal "skipped", result.fetch(:status)
        assert_equal "disabled", result.fetch(:reason)
        assert_equal 0, result.fetch(:attempts)
        assert_equal 0, sink.delivered_events
        assert_equal 0, CheckpointStore.new(sqlite).count
        assert_equal 0, DeliveredEnvelopeStore.new(sqlite).count
      end
    end

    def test_route_mismatch_skips_without_advancing_shared_progress
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = RecordingSink.new
        route_filter = RouteFilter.new("tables" => ["users"])
        worker = build_worker(sqlite, sink: sink, route_filter: route_filter)

        result = worker.deliver(sample_event)

        assert_equal "skipped", result.fetch(:status)
        assert_equal "route_mismatch", result.fetch(:reason)
        assert_equal 0, sink.delivered_events
        assert_equal 0, CheckpointStore.new(sqlite).count
      end
    end

    def test_delivers_transaction_without_advancing_shared_progress
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = RecordingSink.new
        worker = build_worker(sqlite, sink: sink)
        envelope = core_envelope(
          events: [
            core_event(event_id: "event-1", source_position: "0/1"),
            core_event(event_id: "event-2", source_position: "0/2")
          ],
          transaction_id: "tx-1"
        )

        result = worker.deliver_transaction(envelope)
        assert_equal "delivered", result.fetch(:status)
        assert_equal "transaction.committed", result.fetch(:payload_type)
        assert_equal 0, CheckpointStore.new(sqlite).count
        assert_equal envelope, sink.delivered_transactions.fetch(0)
      end
    end

    def test_applies_payload_policy_before_delivery
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = PreparedSink.new
        policy = PayloadPolicy.new("rules" => [{ "columns" => ["email"], "action" => "remove" }])
        worker = build_worker(sqlite, sink: sink, payload_policy: policy)

        result = worker.deliver(sample_event(data: { "id" => 1, "email" => "private@example.com" }))
        payload = sink.payloads.fetch(0)

        assert_equal "delivered", result.fetch(:status)
        refute payload.fetch("data").key?("email")
        assert_equal policy.fingerprint,
                     payload.dig("metadata", PayloadPolicy::POLICY_METADATA_KEY, "fingerprint")
      end
    end

    def test_retries_and_dead_letters_the_same_prepared_payload
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = FailingPreparedSink.new
        policy = PayloadPolicy.new("rules" => [{ "columns" => ["email"], "action" => "remove" }])
        worker = build_worker(sqlite, sink: sink, payload_policy: policy)

        result = worker.deliver(sample_event(data: { "id" => 1, "email" => "private@example.com" }))
        stored = JSON.parse(DeadLetterStore.new(sqlite).pending.fetch(0).fetch("payload_json"))

        assert_equal "dead_lettered", result.fetch(:status)
        assert_equal 3, sink.payloads.length
        assert_prepared_dead_letter(sink, stored, policy)
      end
    end

    def test_exact_payload_replay_does_not_apply_current_policy
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        sink = PreparedSink.new
        policy = PayloadPolicy.new("rules" => [{ "columns" => ["email"], "action" => "mask" }])
        worker = build_worker(sqlite, sink: sink, payload_policy: policy)
        stored = EventSerializer.call(sample_event(data: { "email" => "already-prepared" }))

        worker.deliver_payload(stored)

        assert_same stored, sink.payloads.fetch(0)
        assert_equal "already-prepared", sink.payloads.fetch(0).dig("data", "email")
      end
    end

    def test_active_policy_rejects_sink_without_prepared_payload_support
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        policy = PayloadPolicy.new("rules" => [{ "columns" => ["email"], "action" => "remove" }])

        error = assert_raises(ConfigurationError) do
          build_worker(sqlite, sink: RecordingSink.new, payload_policy: policy)
        end

        assert_match(/does not accept prepared payloads/, error.message)
      end
    end

    def test_exact_payload_replay_rejects_legacy_sink
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        worker = build_worker(sqlite, sink: RecordingSink.new)
        payload = EventSerializer.call(sample_event)

        error = assert_raises(ConfigurationError) { worker.deliver_payload(payload) }

        assert_match(/does not accept prepared payloads/, error.message)
      end
    end

    private

    def assert_prepared_dead_letter(sink, stored, policy)
      assert(sink.payloads.all? { |payload| payload.equal?(sink.payloads.fetch(0)) })
      refute_includes JSON.generate(stored), "private@example.com"
      assert_equal policy.fingerprint,
                   stored.dig("metadata", PayloadPolicy::POLICY_METADATA_KEY, "fingerprint")
    end

    def build_worker(sqlite, sink:, sleeper: ->(_seconds) {}, route_filter: nil, payload_policy: nil, enabled: true,
                     logger: Logging::NullLogger::INSTANCE)
      DeliveryWorker.new(
        sink: sink,
        checkpoint_store: CheckpointStore.new(sqlite),
        dead_letter_store: DeadLetterStore.new(sqlite),
        delivered_envelope_store: DeliveredEnvelopeStore.new(sqlite),
        source_name: "local_mammoth",
        slot_name: "mammoth_prod",
        publication_name: "mammoth_publication",
        max_attempts: 3,
        retry_schedule: [1, 5],
        sleeper: sleeper,
        route_filter: route_filter,
        payload_policy: payload_policy,
        enabled: enabled,
        logger: logger
      )
    end

    def sample_event(data: {})
      core_event(event_id: "event-1", source_position: "0/16F4A8B0", data: data)
    end

    class RecordingSink
      attr_reader :name, :delivered_transactions, :delivered_events

      def initialize
        @name = "primary_webhook"
        @delivered_events = 0
        @delivered_transactions = []
      end

      def deliver(event)
        @delivered_events += 1
        payload = EventSerializer.call(event)
        { event_id: payload.fetch("event_id"), destination: name, status: "delivered", http_status: 200 }
      end

      def deliver_transaction(envelope)
        @delivered_transactions << envelope
        { event_id: "transaction-1", payload_type: "transaction.committed", destination: name, status: "delivered",
          http_status: 200 }
      end
    end

    class FailingSink < RecordingSink
      def deliver(_event)
        raise DeliveryError, "boom"
      end
    end

    class FlakySink < RecordingSink
      def initialize(failures_before_success:)
        super()
        @failures_before_success = failures_before_success
        @attempts = 0
      end

      def deliver(event)
        @attempts += 1
        raise DeliveryError, "temporary" if @attempts <= @failures_before_success

        super
      end
    end

    class PreparedSink
      attr_reader :name, :payloads

      def initialize
        @name = "prepared_webhook"
        @payloads = []
      end

      def deliver_payload(payload)
        payloads << payload
        { event_id: payload.fetch("event_id"), destination: name, status: "delivered", http_status: 200 }
      end
    end

    class FailingPreparedSink < PreparedSink
      def deliver_payload(payload)
        payloads << payload
        raise DeliveryError, "boom"
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
