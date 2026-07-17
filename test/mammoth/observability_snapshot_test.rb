# frozen_string_literal: true

require "json"
require "test_helper"

module Mammoth
  # rubocop:disable Metrics/ClassLength
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

    def test_readiness_reports_ready_when_state_adapter_is_ready
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db"))
        config = Configuration.load(write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: store.path)))
        adapter = OperationalState::SQLiteAdapter.new(store)
        payload = ObservabilitySnapshot.new(config, state_adapter: adapter).readiness

        assert_equal "ready", payload.fetch(:status)
        assert_equal "ok", payload.fetch(:operational_state)
        assert_equal "sqlite", payload.fetch(:adapter)
        assert_includes payload.fetch(:summary).fetch(:tables), "checkpoints"
        assert_includes payload.fetch(:summary).fetch(:tables), "dead_letters"
        assert_includes payload.fetch(:summary).fetch(:tables), "delivered_envelopes"
      end
    end

    def test_readiness_reports_unready_when_state_adapter_fails
      config = Configuration.load(fixture_config_path)
      payload = ObservabilitySnapshot.new(config, state_adapter: UnreadyAdapter.new).readiness

      assert_equal "unready", payload.fetch(:status)
      assert_equal "error", payload.fetch(:operational_state)
      assert_equal "sqlite", payload.fetch(:adapter)
    end

    def test_readiness_reports_adapter_errors
      payload = ObservabilitySnapshot.new(
        Configuration.load(fixture_config_path),
        state_adapter: ErrorAdapter.new
      ).readiness

      assert_equal "unready", payload.fetch(:status)
      assert_equal "Mammoth::StoreError", payload.fetch(:error_class)
      assert_match(/broken adapter/, payload.fetch(:error_message))
    end

    def test_readiness_includes_healthy_active_postgres_slot
      payload = ObservabilitySnapshot.new(
        Configuration.load(fixture_config_path),
        slot_health_provider: SlotHealthProvider.new(postgres_slot_health)
      ).readiness

      assert_equal "ready", payload.fetch(:status)
      assert payload.dig(:postgres_slot, :ready)
      assert_equal 8192, payload.dig(:postgres_slot, :retained_wal_bytes)
      assert_equal "reserved", payload.dig(:postgres_slot, :wal_status)
    end

    def test_readiness_fails_closed_for_inactive_postgres_slot
      health = postgres_slot_health(active: false, inactive_since: "2026-07-17T01:02:03Z")
      payload = ObservabilitySnapshot.new(
        Configuration.load(fixture_config_path),
        slot_health_provider: SlotHealthProvider.new(health)
      ).readiness

      assert_equal "unready", payload.fetch(:status)
      assert_equal "ok", payload.fetch(:operational_state)
      assert_equal "slot is inactive", payload.dig(:postgres_slot, :reason)
    end

    def test_readiness_reports_postgres_inspection_errors
      payload = ObservabilitySnapshot.new(
        Configuration.load(fixture_config_path),
        slot_health_provider: SlotHealthProvider.new(ReplicationError.new("postgres unavailable"))
      ).readiness

      assert_equal "unready", payload.fetch(:status)
      assert_equal "inspection failed", payload.dig(:postgres_slot, :reason)
      assert_match(/postgres unavailable/, payload.dig(:postgres_slot, :error_message))
    end

    # rubocop:disable Metrics/MethodLength
    def test_prometheus_reports_operational_counts
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        config = Configuration.load(write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: store.path)))
        adapter = OperationalState::SQLiteAdapter.new(store)
        adapter.checkpoint_store.write(
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          last_lsn: "0/1"
        )
        adapter.delivered_envelope_store.record!(
          idempotency_key: "key-1",
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          destination_name: "primary_webhook",
          delivery_unit: "transaction",
          transaction_id: "1",
          source_position: "0/1"
        )

        metrics = ObservabilitySnapshot.new(config, state_adapter: adapter).prometheus

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
        adapter = OperationalState::SQLiteAdapter.new(store)
        seed_destination_metrics(adapter)

        metrics = ObservabilitySnapshot.new(config, state_adapter: adapter).prometheus

        assert_includes metrics, %(mammoth_delivered_envelopes_total{mammoth_name="local_mammoth"} 1)
        assert_includes metrics,
                        %(mammoth_delivered_envelopes_total{mammoth_name="local_mammoth",destination="audit_webhook"} 1)
        assert_includes metrics,
                        %(mammoth_dead_letters_pending_total{mammoth_name="local_mammoth",destination="primary_webhook"} 1)
        assert_includes metrics,
                        %(mammoth_dead_letters_pending_total{mammoth_name="local_mammoth",destination="audit_webhook"} 0)
      end
    end

    def test_prometheus_reports_core_dispatch_counters_and_tags
      metrics_registry = DispatchMetrics.new
      observer = MetricsObserver.new(metrics: metrics_registry)
      result = CDC::Core::ProcessorResult.failure(
        DeliveryError.new("boom"),
        event: "event",
        retryable: false,
        processor: "Mammoth::DeliveryProcessor"
      )
      observer.dispatch_started("event")
      observer.dispatch_failed(result)
      metrics_registry.increment("custom.dispatch.metric")

      metrics = ObservabilitySnapshot.new(
        Configuration.load(fixture_config_path),
        dispatch_metrics: metrics_registry
      ).prometheus

      assert_includes metrics, %(mammoth_dispatch_started_total{mammoth_name="local_mammoth",kind="String"} 1)
      assert_includes metrics, %(mammoth_dispatch_failed_total{mammoth_name="local_mammoth")
      assert_includes metrics, %(kind="processor_result")
      assert_includes metrics, %(processor="Mammoth::DeliveryProcessor")
      refute_includes metrics, "custom.dispatch.metric"
    end

    def test_prometheus_reports_postgres_slot_health_and_retained_wal
      health = postgres_slot_health(inactive_since: "2026-07-17T01:02:03Z")
      metrics = ObservabilitySnapshot.new(
        Configuration.load(fixture_config_path),
        slot_health_provider: SlotHealthProvider.new(health)
      ).prometheus

      labels = %(mammoth_name="local_mammoth",slot_name="mammoth_prod")
      assert_includes metrics, %(mammoth_postgres_slot_inspection_up{#{labels}} 1)
      assert_includes metrics, %(mammoth_postgres_slot_ready{#{labels}} 1)
      assert_includes metrics, %(mammoth_postgres_slot_active{#{labels}} 1)
      assert_includes metrics, %(mammoth_postgres_slot_retained_wal_bytes{#{labels}} 8192)
      assert_includes metrics, %(mammoth_postgres_slot_safe_wal_size_bytes{#{labels}} 4096)
      assert_includes metrics, %(mammoth_postgres_slot_restart_lsn_bytes{#{labels}} 16)
      assert_includes metrics, %(mammoth_postgres_slot_confirmed_flush_lsn_bytes{#{labels}} 32)
      assert_includes metrics, %(wal_status="reserved")
      assert_includes metrics, %(mammoth_postgres_slot_inactive_since_timestamp_seconds{#{labels}} 1784250123)
    end

    def test_prometheus_reports_missing_slot_and_inspection_failure
      config = Configuration.load(fixture_config_path)
      missing_metrics = ObservabilitySnapshot.new(
        config,
        slot_health_provider: SlotHealthProvider.new(Sources::PostgresSlotHealth.missing("mammoth_prod"))
      ).prometheus
      error_metrics = ObservabilitySnapshot.new(
        config,
        slot_health_provider: SlotHealthProvider.new(ReplicationError.new("postgres unavailable"))
      ).prometheus

      assert_includes missing_metrics,
                      %(mammoth_postgres_slot_present{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 0)
      refute_includes missing_metrics, "mammoth_postgres_slot_active{"
      assert_includes error_metrics,
                      %(mammoth_postgres_slot_inspection_up{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 0)
      assert_includes error_metrics, %(mammoth_up{mammoth_name="local_mammoth"} 1)
    end

    def test_prometheus_reports_unhealthy_slot_and_tolerates_unknown_optional_values # rubocop:disable Metrics/MethodLength
      health = postgres_slot_health(
        active: false,
        retained_wal_bytes: nil,
        wal_status: nil,
        safe_wal_size: nil,
        inactive_since: Time.utc(2026, 7, 17, 1, 2, 3),
        invalidation_reason: "wal_removed",
        restart_lsn_bytes: nil,
        confirmed_flush_lsn_bytes: nil
      )
      metrics = ObservabilitySnapshot.new(
        Configuration.load(fixture_config_path),
        slot_health_provider: SlotHealthProvider.new(health)
      ).prometheus

      assert_includes metrics, %(mammoth_postgres_slot_ready{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 0)
      assert_includes metrics, %(mammoth_postgres_slot_active{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 0)
      assert_includes metrics, %(wal_status="unknown")
      assert_includes metrics,
                      %(mammoth_postgres_slot_invalidated{mammoth_name="local_mammoth",slot_name="mammoth_prod"} 1)
      refute_includes metrics, "mammoth_postgres_slot_retained_wal_bytes{"
      assert_includes metrics, "mammoth_postgres_slot_inactive_since_timestamp_seconds"
    end

    def test_prometheus_omits_invalid_inactive_since_timestamp
      metrics = ObservabilitySnapshot.new(
        Configuration.load(fixture_config_path),
        slot_health_provider: SlotHealthProvider.new(postgres_slot_health(inactive_since: "not-a-time"))
      ).prometheus

      refute_includes metrics, "mammoth_postgres_slot_inactive_since_timestamp_seconds{"
    end

    def test_prometheus_reports_down_when_store_fails
      metrics = ObservabilitySnapshot.new(
        Configuration.load(fixture_config_path),
        state_adapter: UnreadyAdapter.new
      ).prometheus

      assert_includes metrics, %(mammoth_up{mammoth_name="local_mammoth"} 0)
      refute_includes metrics, "mammoth_checkpoints_total{"
    end

    def test_prometheus_reports_down_when_adapter_raises
      metrics = ObservabilitySnapshot.new(
        Configuration.load(fixture_config_path),
        state_adapter: ErrorAdapter.new
      ).prometheus

      assert_includes metrics, %(mammoth_up{mammoth_name="local_mammoth"} 0)
    end

    class UnreadyAdapter < OperationalState::Adapter
      def ready? = false
    end

    class ErrorAdapter < OperationalState::Adapter
      def ready?
        raise StoreError, "broken adapter"
      end
    end

    SlotHealthProvider = Data.define(:result) do
      def slot_health
        raise result if result.is_a?(Exception)

        result
      end
    end

    private

    def postgres_slot_health(**overrides)
      Sources::PostgresSlotHealth.new(
        slot_name: "mammoth_prod",
        present: true,
        active: true,
        retained_wal_bytes: 8192,
        wal_status: "reserved",
        safe_wal_size: 4096,
        inactive_since: nil,
        invalidation_reason: nil,
        restart_lsn: "0/10",
        restart_lsn_bytes: 16,
        confirmed_flush_lsn: "0/20",
        confirmed_flush_lsn_bytes: 32,
        conflicting: false,
        **overrides
      )
    end

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

    def seed_destination_metrics(adapter)
      adapter.delivered_envelope_store.record!(
        idempotency_key: "key-1",
        source_name: "local_mammoth",
        slot_name: "mammoth_prod",
        destination_name: "audit_webhook",
        delivery_unit: "transaction",
        transaction_id: "1",
        source_position: "0/1"
      )
      adapter.dead_letter_store.write(event: sample_event, destination_name: "primary_webhook")
    end

    def sample_event
      core_event
    end
  end
  # rubocop:enable Metrics/ClassLength
end
