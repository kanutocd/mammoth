# frozen_string_literal: true

require "json"
require "test_helper"
require "webrick"

module Mammoth
  # rubocop:disable Metrics/ClassLength
  class DeadLetterCommandsTest < Minitest::Test
    def test_dead_letters_list_command_prints_pending_rows
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))
        write_dead_letter(db_path)

        stdout, stderr = capture_io do
          assert_equal 0, CLI.call(["dead-letters", "list", config_path])
        end

        assert_empty stderr
        assert_match(/ID\s+STATUS\s+DESTINATION/, stdout)
        assert_match(/event-1/, stdout)
        assert_match(/pending/, stdout)
      end
    end

    def test_dead_letters_list_command_supports_status_and_limit
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))
        store = dead_letter_store(db_path)
        first = store.write(event: sample_event("event-1"), destination_name: "primary_webhook")
        store.write(event: sample_event("event-2"), destination_name: "primary_webhook")
        store.resolve(first)

        stdout, stderr = capture_io do
          assert_equal 0, CLI.call(["dead-letters", "list", config_path, "--status", "all", "--limit", "1"])
        end

        assert_empty stderr
        assert_match(/ID\s+STATUS\s+DESTINATION/, stdout)
        assert_match(/event-1/, stdout)
      end
    end

    def test_dead_letters_list_rejects_unknown_option
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "list", config_path, "--bogus"])
        end

        assert_empty stdout
        assert_match(/unknown option/, stderr)
      end
    end

    def test_dead_letters_list_rejects_unexpected_argument
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "list", config_path, "unexpected"])
        end

        assert_empty stdout
        assert_match(/unexpected argument/, stderr)
      end
    end

    def test_dead_letters_list_rejects_invalid_limit
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "list", config_path, "--limit", "nope"])
        end

        assert_empty stdout
        assert_match(/dead letter limit must be an integer/, stderr)
      end
    end

    def test_dead_letters_list_requires_config_path
      stdout, stderr = capture_io do
        assert_equal 1, CLI.call(%w[dead-letters list])
      end

      assert_empty stdout
      assert_match(/configuration path required/, stderr)
    end

    def test_dead_letters_show_requires_integer_id
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "show", config_path, "abc"])
        end

        assert_empty stdout
        assert_match(/dead letter id must be an integer/, stderr)
      end
    end

    def test_dead_letters_show_requires_dead_letter_id
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "show", config_path])
        end

        assert_empty stdout
        assert_match(/dead letter id required/, stderr)
      end
    end

    def test_dead_letters_show_reports_missing_dead_letter
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "show", config_path, "999"])
        end

        assert_empty stdout
        assert_match(/dead letter not found: 999/, stderr)
      end
    end

    def test_dead_letters_show_prints_payload
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))
        id = write_dead_letter(db_path)

        stdout, stderr = capture_io do
          assert_equal 0, CLI.call(["dead-letters", "show", config_path, id.to_s])
        end

        assert_empty stderr
        assert_match(/"payload"/, stdout)
        assert_match(/"event_id": "event-1"/, stdout)
      end
    end

    def test_dead_letters_replay_requires_integer_id
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "replay", config_path, "abc"])
        end

        assert_empty stdout
        assert_match(/dead letter id must be an integer/, stderr)
      end
    end

    def test_dead_letters_replay_reports_empty_queue
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "replay", config_path])
        end

        assert_empty stdout
        assert_match(/no dead letters found to replay/, stderr)
      end
    end

    def test_dead_letters_replay_reports_missing_dead_letter
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "replay", config_path, "999"])
        end

        assert_empty stdout
        assert_match(/dead letter not found: 999/, stderr)
      end
    end

    def test_dead_letters_replay_command_delivers_and_resolves_row
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        event_id = nil

        with_test_server(200) do |url, received|
          config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path, webhook_url: url))
          event_id = write_dead_letter(db_path)

          stdout, stderr = capture_io do
            assert_equal 0, CLI.call(["dead-letters", "replay", config_path, event_id.to_s])
          end

          assert_empty stderr
          assert_match(/Dead letter #{event_id}: delivered/, stdout)
          assert_match(/"event_id":"event-1"/, received.fetch(:body))
        end

        sqlite = SQLiteStore.connect(db_path).bootstrap!
        store = DeadLetterStore.new(sqlite)

        assert_equal 0, store.count(status: "pending")
        assert_equal 1, store.count(status: "resolved")
      end
    end

    def test_dead_letters_replay_command_delivers_transaction_envelope
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        with_test_server(200) do |url, received|
          config_path, id = transaction_replay_setup(dir, url)

          stdout, stderr = capture_io do
            assert_equal 0, CLI.call(["dead-letters", "replay", config_path])
          end

          assert_empty stderr
          assert_match(/Dead letter #{id}: delivered/, stdout)
          assert_match(/"type":"transaction.committed"/, received.fetch(:body))
        end
        assert_transaction_replay_resolved(db_path)
      end
    end

    def test_dead_letters_replay_targets_fanout_event_destination
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")

        with_two_test_servers do |primary_url, primary_received, audit_url, audit_received|
          config_path = write_file(File.join(dir, "mammoth.yml"), fanout_config(db_path, primary_url, audit_url))
          id = dead_letter_store(db_path).write(
            event: sample_event,
            destination_name: "audit_webhook",
            error: RuntimeError.new("boom"),
            retry_count: 3
          )

          stdout, stderr = capture_io do
            assert_equal 0, CLI.call(["dead-letters", "replay", config_path, id.to_s])
          end

          assert_empty stderr
          assert_match(/Dead letter #{id}: delivered/, stdout)
          assert_nil primary_received[:body]
          assert_match(/"event_id":"event-1"/, audit_received.fetch(:body))
        end
      end
    end

    def test_dead_letters_replay_targets_fanout_transaction_destination
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")

        with_two_test_servers do |primary_url, primary_received, audit_url, audit_received|
          config_path = write_file(File.join(dir, "mammoth.yml"), fanout_config(db_path, primary_url, audit_url))
          id = write_fanout_transaction_dead_letter(db_path)

          stdout, stderr = capture_io do
            assert_equal 0, CLI.call(["dead-letters", "replay", config_path, id.to_s])
          end

          assert_empty stderr
          assert_match(/Dead letter #{id}: delivered/, stdout)
          assert_nil primary_received[:body]
          assert_match(/"type":"transaction.committed"/, audit_received.fetch(:body))
        end
      end
    end

    def test_dead_letters_replay_keeps_pending_when_destination_is_disabled
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), disabled_audit_fanout_config(db_path))
        id = dead_letter_store(db_path).write(event: sample_event, destination_name: "audit_webhook")

        stdout, stderr = capture_io do
          assert_equal 0, CLI.call(["dead-letters", "replay", config_path, id.to_s])
        end

        assert_empty stderr
        assert_match(/Dead letter #{id}: skipped/, stdout)
        assert_equal 1, dead_letter_store(db_path).count(status: "pending")
        assert_equal 0, dead_letter_store(db_path).count(status: "resolved")
      end
    end

    def test_dead_letters_replay_filters_by_destination_status_and_time_window
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")

        with_two_test_servers do |primary_url, _primary_received, audit_url, _audit_received|
          config_path = write_file(File.join(dir, "mammoth.yml"), fanout_config(db_path, primary_url, audit_url))
          store = dead_letter_store(db_path)
          ids = write_time_window_dead_letters(store)

          stdout, stderr = capture_io do
            assert_equal 0, CLI.call(filtered_replay_command(config_path))
          end

          assert_empty stderr
          assert_match(/Dead letter #{ids.fetch(:replay_id)}: delivered/, stdout)
          refute_match(/Dead letter #{ids.fetch(:old_id)}:/, stdout)
          assert_equal 2, store.count(status: "pending")
          assert_equal 1, store.count(status: "resolved")
        end
      end
    end

    def test_dead_letters_replay_rejects_invalid_time_window
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "replay", config_path, "--failed-after", "not-time"])
        end

        assert_empty stdout
        assert_match(/--failed-after must be an ISO-8601 timestamp/, stderr)
      end
    end

    def test_dead_letters_replay_rejects_unknown_option
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "replay", config_path, "--bogus"])
        end

        assert_empty stdout
        assert_match(/unexpected argument --bogus/, stderr)
      end
    end

    def test_dead_letters_list_rejects_invalid_failed_before
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "list", config_path, "--failed-before", "not-time"])
        end

        assert_empty stdout
        assert_match(/--failed-before must be an ISO-8601 timestamp/, stderr)
      end
    end

    def test_dead_letters_list_rejects_missing_option_value
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["dead-letters", "list", config_path, "--destination"])
        end

        assert_empty stdout
        assert_match(/missing value for dead letter option/, stderr)
      end
    end

    def test_dead_letters_replay_keeps_pending_when_delivery_still_fails
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")

        with_test_server(500) do |url, _received|
          config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path, webhook_url: url))
          id = write_dead_letter(db_path)

          Kernel.stub(:sleep, 0) do
            stdout, stderr = capture_io do
              assert_equal 0, CLI.call(["dead-letters", "replay", config_path])
            end

            assert_empty stderr
            assert_match(/Dead letter #{id}: dead_lettered/, stdout)
          end
        end

        sqlite = SQLiteStore.connect(db_path).bootstrap!
        store = DeadLetterStore.new(sqlite)

        assert_equal 2, store.count(status: "pending")
      end
    end

    def test_dead_letters_missing_subcommand
      stdout, stderr = capture_io do
        assert_equal 1, CLI.call(["dead-letters"])
      end

      assert_empty stdout
      assert_match(/dead-letters subcommand required/, stderr)
    end

    private

    def sample_event(event_id = "event-1")
      {
        "event_id" => event_id,
        "source" => "postgresql",
        "operation" => "insert",
        "namespace" => "public",
        "entity" => "orders",
        "source_position" => "0/1",
        "data" => { "id" => 1 }
      }
    end

    def write_dead_letter(db_path)
      dead_letter_store(db_path).write(
        event: sample_event,
        destination_name: "primary_webhook",
        error: RuntimeError.new("boom"),
        retry_count: 3
      )
    end

    def dead_letter_store(db_path)
      DeadLetterStore.new(SQLiteStore.connect(db_path).bootstrap!)
    end

    def transaction_envelope(events)
      Data.define(:events, :transaction_id).new(events, "tx-1")
    end

    def transaction_replay_setup(dir, webhook_url)
      db_path = File.join(dir, "mammoth.db")
      transaction_event = sample_event.merge("event_id" => "transaction-event-1", "source_position" => "0/2")
      transaction = transaction_envelope([transaction_event])
      config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path, webhook_url: webhook_url))
      id = dead_letter_store(db_path).write(
        event: transaction,
        destination_name: "primary_webhook",
        error: RuntimeError.new("boom"),
        retry_count: 5,
        serializer: TransactionEnvelopeSerializer
      )

      [config_path, id]
    end

    def fanout_config(db_path, primary_url, audit_url)
      minimal_config(sqlite_path: db_path).sub(/^webhook:.*?(?=^retry:)/m, <<~YAML)
        destinations:
          - name: primary_webhook
            type: webhook
            url: #{primary_url}
            timeout_seconds: 5
          - name: audit_webhook
            type: webhook
            url: #{audit_url}
            timeout_seconds: 5

      YAML
    end

    def disabled_audit_fanout_config(db_path)
      fanout_config(db_path, "https://example.com/primary", "https://example.com/audit").sub(
        "name: audit_webhook\n    type: webhook",
        "name: audit_webhook\n    type: webhook\n    enabled: false"
      )
    end

    def write_fanout_transaction_dead_letter(db_path)
      transaction = transaction_envelope([sample_event.merge("event_id" => "transaction-event-1")])
      dead_letter_store(db_path).write(
        event: transaction,
        destination_name: "audit_webhook",
        error: RuntimeError.new("boom"),
        retry_count: 3,
        serializer: TransactionEnvelopeSerializer
      )
    end

    def write_time_window_dead_letters(store)
      old_id = store.write(event: sample_event("old-audit"), destination_name: "audit_webhook")
      replay_id = store.write(event: sample_event("new-audit"), destination_name: "audit_webhook")
      store.write(event: sample_event("new-primary"), destination_name: "primary_webhook")
      store.sqlite_store.database.execute("UPDATE dead_letters SET failed_at = ? WHERE id = ?",
                                          ["2026-07-05T00:00:00Z", old_id])
      store.sqlite_store.database.execute("UPDATE dead_letters SET failed_at = ? WHERE id = ?",
                                          ["2026-07-06T00:00:00Z", replay_id])
      { old_id: old_id, replay_id: replay_id }
    end

    def filtered_replay_command(config_path)
      [
        "dead-letters", "replay", config_path,
        "--destination", "audit_webhook",
        "--status", "pending",
        "--failed-after", "2026-07-05T12:00:00Z"
      ]
    end

    def assert_transaction_replay_resolved(db_path)
      sqlite = SQLiteStore.connect(db_path).bootstrap!
      store = DeadLetterStore.new(sqlite)

      assert_equal 0, store.count(status: "pending")
      assert_equal 1, store.count(status: "resolved")
    end

    def with_test_server(status)
      received = {}
      server = WEBrick::HTTPServer.new(Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      server.mount_proc "/webhook" do |request, response|
        received[:body] = request.body
        response.status = status
        response.body = "ok"
      end
      thread = Thread.new { server.start }
      yield "http://127.0.0.1:#{server.config.fetch(:Port)}/webhook", received
    ensure
      server&.shutdown
      thread&.join
    end

    def with_two_test_servers
      with_test_server(200) do |primary_url, primary_received|
        with_test_server(200) do |audit_url, audit_received|
          yield primary_url, primary_received, audit_url, audit_received
        end
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
