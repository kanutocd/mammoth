# frozen_string_literal: true

require "test_helper"
require "json"
require "webrick"

module Mammoth
  class CLITest < Minitest::Test
    def test_version_command
      stdout, stderr = capture_io do
        assert_equal 0, CLI.call(["version"])
      end

      assert_equal "Mammoth #{Mammoth::VERSION}\n", stdout
      assert_empty stderr
    end

    def test_unknown_command_prints_usage
      stdout, stderr = capture_io do
        assert_equal 1, CLI.call(["unknown"])
      end

      assert_empty stdout
      assert_match(/Usage:/, stderr)
    end

    def test_validate_command
      stdout, stderr = capture_io do
        assert_equal 0, CLI.call(["validate", fixture_config_path])
      end

      assert_match(/Configuration OK:/, stdout)
      assert_empty stderr
    end

    def test_validate_requires_config_path
      stdout, stderr = capture_io do
        assert_equal 1, CLI.call(["validate"])
      end

      assert_empty stdout
      assert_match(/configuration path required/, stderr)
    end

    def test_bootstrap_command_initializes_sqlite
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 0, CLI.call(["bootstrap", config_path])
        end

        assert_empty stderr
        assert_match(/SQLite database initialized/, stdout)
        assert File.file?(db_path)
      end
    end

    def test_status_command_prints_operational_snapshot
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config_path = write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: db_path))

        stdout, stderr = capture_io do
          assert_equal 0, CLI.call(["status", config_path])
        end

        assert_empty stderr
        assert_match(/Mammoth: local_mammoth/, stdout)
        assert_match(/Runtime: not started/, stdout)
        assert_match(/Tables:/, stdout)
      end
    end

    def test_start_command_prints_delivered_count
      fake_app = Object.new
      def fake_app.start = 7

      Application.stub(:new, fake_app) do
        stdout, stderr = capture_io do
          assert_equal 0, CLI.call(["start", fixture_config_path])
        end

        assert_empty stderr
        assert_match(/Delivered events: 7/, stdout)
      end
    end

    def test_deliver_sample_command_processes_event
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        event_path = write_file(File.join(dir, "event.json"), JSON.generate(sample_event))

        with_test_server(200) do |url, _received|
          config_path = write_file(
            File.join(dir, "mammoth.yml"),
            minimal_config(sqlite_path: db_path, webhook_url: url)
          )

          stdout, stderr = capture_io do
            assert_equal 0, CLI.call(["deliver-sample", config_path, event_path])
          end

          assert_empty stderr
          assert_match(/Delivered sample events: 1/, stdout)
          assert_equal 1, CheckpointStore.new(SQLiteStore.connect(db_path).bootstrap!).count
        end
      end
    end

    def test_deliver_sample_requires_event_path
      stdout, stderr = capture_io do
        assert_equal 1, CLI.call(["deliver-sample", fixture_config_path])
      end

      assert_empty stdout
      assert_match(/event JSON path required/, stderr)
    end

    def test_deliver_sample_reports_missing_event_file
      with_temp_dir do |dir|
        missing_event_path = File.join(dir, "missing.json")

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["deliver-sample", fixture_config_path, missing_event_path])
        end

        assert_empty stdout
        assert_match(/event JSON file not found/, stderr)
      end
    end

    def test_deliver_sample_reports_invalid_json
      with_temp_dir do |dir|
        event_path = write_file(File.join(dir, "event.json"), "{")

        stdout, stderr = capture_io do
          assert_equal 1, CLI.call(["deliver-sample", fixture_config_path, event_path])
        end

        assert_empty stdout
        assert_match(/invalid event JSON/, stderr)
      end
    end

    private

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
  end
end
