# frozen_string_literal: true

require "test_helper"
require "openssl"
require "webrick"

module Mammoth
  # rubocop:disable Metrics/ClassLength
  class WebhookSinkTest < Minitest::Test
    def test_from_config_builds_sink
      config = Configuration.load(fixture_config_path)
      sink = WebhookSink.from_config(config)

      assert_equal "primary_webhook", sink.name
      assert_equal 5, sink.timeout_seconds
      assert_equal "local_mammoth", sink.headers.fetch("X-Mammoth-Source")
    end

    def test_delivers_event_to_webhook
      with_test_server(201) do |url, received|
        sink = WebhookSink.new(name: "primary_webhook", url: url, timeout_seconds: 2)
        result = sink.deliver(core_event(event_id: "event-1", data: { "id" => 1 }))

        assert_equal "delivered", result.fetch(:status)
        assert_equal 201, result.fetch(:http_status)
        assert_match(/event-1/, received.fetch(:body))
      end
    end

    def test_delivers_an_exact_prepared_payload
      payload = {
        "event_id" => "event-prepared",
        "source" => "postgresql",
        "source_position" => "0/1",
        "metadata" => { "mammoth_payload_policy" => { "fingerprint" => "sha256:test" } }
      }

      with_test_server(201) do |url, received|
        sink = WebhookSink.new(name: "primary_webhook", url: url, timeout_seconds: 2)
        sink.deliver_payload(payload)

        assert_equal payload, JSON.parse(received.fetch(:body))
      end
    end

    def test_sends_configured_static_and_env_headers
      original_token = ENV["MAMMOTH_WEBHOOK_TOKEN"]
      ENV["MAMMOTH_WEBHOOK_TOKEN"] = "Bearer test-token"

      with_test_server(204) do |url, received|
        sink = WebhookSink.new(
          name: "primary_webhook",
          url: url,
          timeout_seconds: 2,
          headers: {
            "X-Static" => "static-value",
            "Authorization" => ENV.fetch("MAMMOTH_WEBHOOK_TOKEN")
          }
        )

        sink.deliver(core_event(event_id: "event-headers"))

        assert_equal "static-value", received.fetch(:headers).fetch("x-static").fetch(0)
        assert_equal "Bearer test-token", received.fetch(:headers).fetch("authorization").fetch(0)
      end
    ensure
      ENV["MAMMOTH_WEBHOOK_TOKEN"] = original_token
    end

    def test_from_config_resolves_env_headers
      original_token = ENV["MAMMOTH_WEBHOOK_TOKEN"]
      ENV["MAMMOTH_WEBHOOK_TOKEN"] = "Bearer configured-token"
      config = Configuration.load(fixture_config_path)
      config.data.fetch("webhook")["header_env"] = { "Authorization" => "MAMMOTH_WEBHOOK_TOKEN" }

      sink = WebhookSink.from_config(config)

      assert_equal "Bearer configured-token", sink.headers.fetch("Authorization")
    ensure
      ENV["MAMMOTH_WEBHOOK_TOKEN"] = original_token
    end

    def test_from_config_rejects_missing_env_header
      config = Configuration.load(fixture_config_path)
      config.data.fetch("webhook")["header_env"] = { "Authorization" => "MAMMOTH_MISSING_WEBHOOK_TOKEN" }

      error = assert_raises(ConfigurationError) { WebhookSink.from_config(config) }

      assert_match(/MAMMOTH_MISSING_WEBHOOK_TOKEN/, error.message)
    end

    def test_signs_webhook_request_body
      with_test_server(204) do |url, received|
        sink = WebhookSink.new(
          name: "primary_webhook",
          url: url,
          timeout_seconds: 2,
          signing: {
            secret: "test-secret",
            signature_header: "X-Test-Signature",
            timestamp_header: "X-Test-Timestamp"
          }
        )

        sink.deliver(core_event(event_id: "event-signed"))

        timestamp = received.fetch(:headers).fetch("x-test-timestamp").fetch(0)
        signature = received.fetch(:headers).fetch("x-test-signature").fetch(0)
        expected = OpenSSL::HMAC.hexdigest("SHA256", "test-secret", "#{timestamp}.#{received.fetch(:body)}")
        assert_equal "sha256=#{expected}", signature
      end
    end

    def test_from_config_resolves_signing_defaults
      original_secret = ENV["MAMMOTH_WEBHOOK_SIGNING_SECRET"]
      ENV["MAMMOTH_WEBHOOK_SIGNING_SECRET"] = "configured-secret"
      config = Configuration.load(fixture_config_path)
      config.data.fetch("webhook")["signing"] = { "secret_env" => "MAMMOTH_WEBHOOK_SIGNING_SECRET" }

      sink = WebhookSink.from_config(config)

      assert_equal "configured-secret", sink.signing.fetch(:secret)
      assert_equal "X-Mammoth-Signature", sink.signing.fetch(:signature_header)
      assert_equal "X-Mammoth-Timestamp", sink.signing.fetch(:timestamp_header)
    ensure
      ENV["MAMMOTH_WEBHOOK_SIGNING_SECRET"] = original_secret
    end

    def test_from_config_rejects_unsupported_signing_algorithm
      config = Configuration.load(fixture_config_path)
      config.data.fetch("webhook")["signing"] = {
        "algorithm" => "rsa_sha256",
        "secret_env" => "MAMMOTH_WEBHOOK_SIGNING_SECRET"
      }

      error = assert_raises(ConfigurationError) { WebhookSink.from_config(config) }

      assert_match(/webhook.signing.algorithm/, error.message)
    end

    def test_from_config_rejects_missing_signing_secret_env
      config = Configuration.load(fixture_config_path)
      config.data.fetch("webhook")["signing"] = { "secret_env" => "MAMMOTH_MISSING_WEBHOOK_SECRET" }

      error = assert_raises(ConfigurationError) { WebhookSink.from_config(config) }

      assert_match(/MAMMOTH_MISSING_WEBHOOK_SECRET/, error.message)
    end

    def test_delivers_transaction_envelope_to_webhook
      with_test_server(202) do |url, received|
        sink = WebhookSink.new(name: "primary_webhook", url: url, timeout_seconds: 2)
        envelope = core_envelope(
          events: [core_event(event_id: "event-1", source_position: "0/1")],
          transaction_id: "tx-1"
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
          sink.deliver(core_event(event_id: "event-1"))
        end

        assert_match(/HTTP 500/, error.message)
      end
    end

    def test_raises_delivery_error_for_unreachable_host
      sink = WebhookSink.new(name: "primary_webhook", url: "http://127.0.0.1:1/webhook", timeout_seconds: 1)

      assert_raises(DeliveryError) { sink.deliver(core_event(event_id: "event-1")) }
    end

    private

    def with_test_server(status)
      received = {}
      server = WEBrick::HTTPServer.new(Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      server.mount_proc "/webhook" do |request, response|
        received[:body] = request.body
        received[:headers] = request.header
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
  # rubocop:enable Metrics/ClassLength
end
