# frozen_string_literal: true

require "json"
require "test_helper"

module Mammoth
  class ObservabilitySnapshotTest < Minitest::Test
    def test_health_payload_is_stable
      with_temp_dir do |dir|
        config_path = write_file(
          File.join(dir, "mammoth.yml"),
          minimal_config(sqlite_path: File.join(dir, "mammoth.db"))
        )
        config = Configuration.load(config_path)
        snapshot = ObservabilitySnapshot.new(config, clock: -> { Time.utc(2026, 7, 6, 1, 2, 3) })

        assert_equal(
          {
            status: "ok",
            service: "mammoth",
            name: "local_mammoth",
            version: Mammoth::VERSION,
            checked_at: "2026-07-06T01:02:03Z"
          },
          snapshot.health
        )
      end
    end

    def test_readiness_reports_ready_when_sqlite_bootstraps
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db"))
        config = Configuration.load(write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: store.path)))
        payload = ObservabilitySnapshot.new(config, sqlite_store: store).readiness

        assert_equal "ready", payload.fetch(:status)
        assert_equal "ok", payload.fetch(:sqlite)
        assert_includes payload.fetch(:tables), "checkpoints"
        assert_includes payload.fetch(:tables), "dead_letters"
        assert_includes payload.fetch(:tables), "delivered_envelopes"
      end
    end

    def test_readiness_reports_unready_when_sqlite_fails
      config = Configuration.load(fixture_config_path)
      store = BrokenStore.new
      payload = ObservabilitySnapshot.new(config, sqlite_store: store).readiness

      assert_equal "unready", payload.fetch(:status)
      assert_equal "error", payload.fetch(:sqlite)
      assert_match(/broken/, payload.fetch(:error_message))
    end

    # rubocop:disable Metrics/MethodLength
    def test_prometheus_reports_operational_counts
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        config = Configuration.load(write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: store.path)))
        CheckpointStore.new(store).write(
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          last_lsn: "0/1"
        )
        DeliveredEnvelopeStore.new(store).record!(
          idempotency_key: "key-1",
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          destination_name: "primary_webhook",
          delivery_unit: "transaction",
          transaction_id: "1",
          source_position: "0/1"
        )

        metrics = ObservabilitySnapshot.new(config, sqlite_store: store).prometheus

        assert_includes metrics, %(mammoth_up{mammoth_name="local_mammoth"} 1)
        assert_includes metrics, %(mammoth_checkpoints_total{mammoth_name="local_mammoth"} 1)
        assert_includes metrics, %(mammoth_delivered_envelopes_total{mammoth_name="local_mammoth"} 1)
        assert_includes metrics, %(mammoth_dead_letters_pending_total{mammoth_name="local_mammoth"} 0)
      end
    end
    # rubocop:enable Metrics/MethodLength

    def test_prometheus_reports_destination_labeled_counts
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        config = Configuration.load(write_file(File.join(dir, "mammoth.yml"), fanout_config(store.path)))
        seed_destination_metrics(store)

        metrics = ObservabilitySnapshot.new(config, sqlite_store: store).prometheus

        assert_includes metrics, %(mammoth_delivered_envelopes_total{mammoth_name="local_mammoth"} 1)
        assert_includes metrics,
                        %(mammoth_delivered_envelopes_total{mammoth_name="local_mammoth",destination="audit_webhook"} 1)
        assert_includes metrics,
                        %(mammoth_dead_letters_pending_total{mammoth_name="local_mammoth",destination="primary_webhook"} 1)
        assert_includes metrics,
                        %(mammoth_dead_letters_pending_total{mammoth_name="local_mammoth",destination="audit_webhook"} 0)
      end
    end

    def test_prometheus_reports_down_when_store_fails
      metrics = ObservabilitySnapshot.new(Configuration.load(fixture_config_path), sqlite_store: BrokenStore.new).prometheus

      assert_includes metrics, %(mammoth_up{mammoth_name="local_mammoth"} 0)
      refute_includes metrics, "mammoth_checkpoints_total{"
    end

    class BrokenStore
      def bootstrap!
        raise StoreError, "broken sqlite"
      end
    end

    private

    def fanout_config(sqlite_path)
      minimal_config(sqlite_path: sqlite_path).sub(/^webhook:.*?(?=^retry:)/m, <<~YAML)
        destinations:
          - name: primary_webhook
            type: webhook
            url: https://example.com/webhooks/postgres
            timeout_seconds: 5
          - name: audit_webhook
            type: webhook
            url: https://example.com/webhooks/audit
            timeout_seconds: 5

      YAML
    end

    def seed_destination_metrics(store)
      DeliveredEnvelopeStore.new(store).record!(
        idempotency_key: "key-1",
        source_name: "local_mammoth",
        slot_name: "mammoth_prod",
        destination_name: "audit_webhook",
        delivery_unit: "transaction",
        transaction_id: "1",
        source_position: "0/1"
      )
      DeadLetterStore.new(store).write(event: sample_event, destination_name: "primary_webhook")
    end

    def sample_event
      {
        "event_id" => "event-1",
        "source" => "postgresql",
        "operation" => "insert",
        "namespace" => "public",
        "entity" => "orders",
        "source_position" => "0/1",
        "data" => { "id" => 1 }
      }
    end
  end
end
