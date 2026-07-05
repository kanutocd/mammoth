# frozen_string_literal: true

require "test_helper"
require "json"
require "openssl"
require "webrick"
require "yaml"

module Mammoth
  class DeliveryE2ETest < Minitest::Test
    def test_delivers_real_http_request_and_persists_sqlite_checkpoint
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        event_path = write_file(File.join(dir, "event.json"), JSON.generate(event_payload))

        with_receiver do |url, received|
          config_path = write_file(
            File.join(dir, "mammoth.yml"),
            minimal_config(sqlite_path: db_path, webhook_url: url)
          )

          assert_equal 0, CLI.call(["deliver-sample", config_path, event_path])

          assert File.file?(db_path)
          assert_match(/event-e2e/, received.fetch(:body))
          store = SQLiteStore.connect(db_path).bootstrap!
          assert_equal 1, CheckpointStore.new(store).count
          assert_equal 0, DeadLetterStore.new(store).count
        end
      end
    end

    def test_skips_duplicate_delivery_across_cli_runs_with_same_sqlite_store
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        event_path = write_file(File.join(dir, "event.json"), JSON.generate(event_payload))

        with_receiver do |url, received|
          config_path = write_config(dir, sqlite_path: db_path, webhook_url: url)

          assert_equal 0, CLI.call(["deliver-sample", config_path, event_path])
          assert_equal 0, CLI.call(["deliver-sample", config_path, event_path])

          store = SQLiteStore.connect(db_path).bootstrap!
          assert_equal 1, received.fetch(:bodies).length
          assert_equal 1, DeliveredEnvelopeStore.new(store).count
          assert_equal 1, CheckpointStore.new(store).count
        end
      end
    end

    def test_delivers_transaction_payload_when_configured
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        event_path = write_file(File.join(dir, "event.json"), JSON.generate(event_payload))

        with_receiver do |url, received|
          config_path = write_config(dir, sqlite_path: db_path, webhook_url: url, delivery_unit: "transaction")

          assert_equal 0, CLI.call(["deliver-sample", config_path, event_path])

          payload = JSON.parse(received.fetch(:bodies).fetch(0))
          assert_equal "transaction.committed", payload.fetch("type")
          assert_equal 1, payload.fetch("event_count")
          assert_equal "event-e2e", payload.fetch("events").fetch(0).fetch("event_id")
        end
      end
    end

    def test_dead_letters_after_http_failure
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        event_path = write_file(File.join(dir, "event.json"), JSON.generate(event_payload))

        with_receiver(status: 500) do |url, _received|
          config_path = write_config(dir, sqlite_path: db_path, webhook_url: url, max_attempts: 1)

          assert_equal 0, CLI.call(["deliver-sample", config_path, event_path])

          store = SQLiteStore.connect(db_path).bootstrap!
          dead_letters = DeadLetterStore.new(store)
          assert_equal 1, dead_letters.count(status: "pending")
          assert_equal 0, CheckpointStore.new(store).count
          assert_equal "event-e2e", dead_letters.pending.fetch(0).fetch("event_id")
        end
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def test_delivers_with_env_auth_header_and_signature
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        event_path = write_file(File.join(dir, "event.json"), JSON.generate(event_payload))
        original_token = ENV["MAMMOTH_E2E_WEBHOOK_TOKEN"]
        original_secret = ENV["MAMMOTH_E2E_WEBHOOK_SECRET"]
        ENV["MAMMOTH_E2E_WEBHOOK_TOKEN"] = "Bearer e2e-token"
        ENV["MAMMOTH_E2E_WEBHOOK_SECRET"] = "e2e-secret"

        with_receiver do |url, received|
          config_path = write_config(dir, sqlite_path: db_path, webhook_url: url, auth: true, signing: true)

          assert_equal 0, CLI.call(["deliver-sample", config_path, event_path])

          headers = received.fetch(:headers)
          timestamp = headers.fetch("x-mammoth-timestamp").fetch(0)
          signature = headers.fetch("x-mammoth-signature").fetch(0)
          expected = OpenSSL::HMAC.hexdigest("SHA256", "e2e-secret", "#{timestamp}.#{received.fetch(:body)}")
          assert_equal "Bearer e2e-token", headers.fetch("authorization").fetch(0)
          assert_equal "sha256=#{expected}", signature
        end
      ensure
        ENV["MAMMOTH_E2E_WEBHOOK_TOKEN"] = original_token
        ENV["MAMMOTH_E2E_WEBHOOK_SECRET"] = original_secret
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    def event_payload
      {
        "event_id" => "event-e2e",
        "operation" => "insert",
        "namespace" => "public",
        "entity" => "orders",
        "source_position" => "0/E2E",
        "data" => { "id" => 123 }
      }
    end

    def write_config(dir, sqlite_path:, webhook_url:, delivery_unit: nil, max_attempts: nil, auth: false, signing: false)
      config = YAML.safe_load(minimal_config(sqlite_path: sqlite_path, webhook_url: webhook_url), aliases: false)
      config["delivery"] = { "unit" => delivery_unit } if delivery_unit
      config["retry"]["max_attempts"] = max_attempts if max_attempts
      config["webhook"]["header_env"] = { "Authorization" => "MAMMOTH_E2E_WEBHOOK_TOKEN" } if auth
      if signing
        config["webhook"]["signing"] = {
          "algorithm" => "hmac_sha256",
          "secret_env" => "MAMMOTH_E2E_WEBHOOK_SECRET"
        }
      end
      write_file(File.join(dir, "mammoth.yml"), YAML.dump(config))
    end

    def with_receiver(status: 204)
      received = { bodies: [] }
      server = WEBrick::HTTPServer.new(Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      server.mount_proc "/webhook" do |request, response|
        received[:body] = request.body
        received[:bodies] << request.body
        received[:headers] = request.header
        response.status = status
      end
      thread = Thread.new { server.start }
      yield "http://127.0.0.1:#{server.config.fetch(:Port)}/webhook", received
    ensure
      server&.shutdown
      thread&.join
    end
  end
end
