# frozen_string_literal: true

require "test_helper"
require "webrick"

module Mammoth
  class WebhookSinkTest < Minitest::Test
    def test_from_config_builds_sink
      config = Configuration.load(fixture_config_path)
      sink = WebhookSink.from_config(config)

      assert_equal "primary_webhook", sink.name
      assert_equal 5, sink.timeout_seconds
    end

    def test_delivers_event_to_webhook
      with_test_server(201) do |url, received|
        sink = WebhookSink.new(name: "primary_webhook", url: url, timeout_seconds: 2)
        result = sink.deliver("event_id" => "event-1", "operation" => "insert", "data" => { "id" => 1 })

        assert_equal "delivered", result.fetch(:status)
        assert_equal 201, result.fetch(:http_status)
        assert_match(/event-1/, received.fetch(:body))
      end
    end

    def test_delivers_transaction_envelope_to_webhook
      with_test_server(202) do |url, received|
        sink = WebhookSink.new(name: "primary_webhook", url: url, timeout_seconds: 2)
        envelope = FakeEnvelope.new(
          [{ "event_id" => "event-1", "operation" => "insert", "source_position" => "0/1" }],
          "tx-1"
        )

        result = sink.deliver_transaction(envelope)

        assert_equal "delivered", result.fetch(:status)
        assert_equal "transaction.committed", result.fetch(:payload_type)
        assert_match(/transaction.committed/, received.fetch(:body))
      end
    end

    def test_raises_delivery_error_for_non_success_status
      with_test_server(500) do |url, _received|
        sink = WebhookSink.new(name: "primary_webhook", url: url, timeout_seconds: 2)

        error = assert_raises(DeliveryError) do
          sink.deliver("event_id" => "event-1", "operation" => "insert")
        end

        assert_match(/HTTP 500/, error.message)
      end
    end

    def test_raises_delivery_error_for_unreachable_host
      sink = WebhookSink.new(name: "primary_webhook", url: "http://127.0.0.1:1/webhook", timeout_seconds: 1)

      assert_raises(DeliveryError) { sink.deliver("event_id" => "event-1", "operation" => "insert") }
    end

    FakeEnvelope = Data.define(:events, :transaction_id)

    private

    def with_test_server(status)
      received = {}
      server = WEBrick::HTTPServer.new(Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      server.mount_proc "/webhook" do |request, response|
        received[:body] = request.body
        response.status = status
        response.body = "ok"
      end
      thread = Thread.new { server.start }
      port = server.config.fetch(:Port)
      yield "http://127.0.0.1:#{port}/webhook", received
    ensure
      server&.shutdown
      thread&.join
    end
  end
end
