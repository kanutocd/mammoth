# frozen_string_literal: true

require "test_helper"

module Mammoth
  class StatusTest < Minitest::Test
    def test_prints_status_without_sqlite_store
      config = Configuration.load(fixture_config_path)

      stdout, stderr = capture_io { Status.call(config) }

      assert_empty stderr
      assert_match(/Mammoth: local_mammoth/, stdout)
      assert_match(/Node ID: local-mammoth-1/, stdout)
      assert_match(/Node name: local-mammoth-dev/, stdout)
      assert_match(/Fleet: local-dev/, stdout)
      assert_match(/Environment: development/, stdout)
      assert_match(/Runtime: not started/, stdout)
      assert_match(/Runtime adapter: concurrent/, stdout)
      assert_match(/Operational state: sqlite/, stdout)
      assert_match(/Features: .*routing/, stdout)
      assert_match(/Replication publications: mammoth_publication/, stdout)
      assert_match(/Destinations: primary_webhook/, stdout)
      refute_match(/Tables:/, stdout)
    end

    def test_prints_fanout_destinations
      with_temp_dir do |dir|
        config_path = write_file(
          File.join(dir, "mammoth.yml"),
          minimal_config(sqlite_path: File.join(dir, "mammoth.db")).sub(/^webhook:.*?(?=^retry:)/m, <<~YAML)
            destinations:
              - name: primary_webhook
                type: webhook
                url: https://example.com/webhooks/postgres
                timeout_seconds: 5
              - name: audit_webhook
                type: webhook
                url: https://audit.example.com/cdc
                timeout_seconds: 5

          YAML
        )

        stdout, stderr = capture_io { Status.call(Configuration.load(config_path)) }

        assert_empty stderr
        assert_match(/Destinations: primary_webhook, audit_webhook/, stdout)
      end
    end

    def test_prints_state_adapter_summary_without_sqlite_store_access
      config = Configuration.load(fixture_config_path)
      adapter = SummaryAdapter.new

      stdout, stderr = capture_io { Status.call(config, state_adapter: adapter) }

      assert_empty stderr
      assert_match(/Operational state ready: true/, stdout)
      assert_match(/Adapter: memory/, stdout)
      assert_match(/Checkpoints: 2/, stdout)
      assert_match(/Delivered envelopes: 4/i, stdout)
      refute_respond_to adapter, :sqlite_store
    end

    class SummaryAdapter < OperationalState::Adapter
      def ready? = true

      def summary
        { adapter: "memory", checkpoints: 2, dead_letters: 3, delivered_envelopes: 4 }
      end
    end
  end
end
