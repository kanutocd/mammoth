# frozen_string_literal: true

require "test_helper"
require "json"
require "webrick"

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

    def with_receiver
      received = {}
      server = WEBrick::HTTPServer.new(Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      server.mount_proc "/webhook" do |request, response|
        received[:body] = request.body
        response.status = 204
      end
      thread = Thread.new { server.start }
      yield "http://127.0.0.1:#{server.config.fetch(:Port)}/webhook", received
    ensure
      server&.shutdown
      thread&.join
    end
  end
end
