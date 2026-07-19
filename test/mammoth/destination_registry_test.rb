# frozen_string_literal: true

require "test_helper"

module Mammoth
  class DestinationRegistryTest < Minitest::Test
    def test_webhook_adapter_is_registered
      assert_same Destinations::WebhookAdapter, Destinations::Registry.fetch("webhook")
      assert_includes Destinations::Registry.names, "webhook"
      assert_equal "adapter", Destinations::Adapter.adapter_type
      assert_equal({ type: "adapter" }, Destinations::Adapter.capabilities)
      assert_equal "custom", CustomAdapter.adapter_type
      assert_equal "webhook", Destinations::WebhookAdapter.adapter_type
      assert Destinations::WebhookAdapter.capabilities.fetch(:signing)
      assert Destinations::WebhookAdapter.capabilities.fetch(:prepared_payloads)
    end

    def test_builds_webhook_sink
      sink = Destinations::Registry.build(
        {
          "name" => "primary_webhook",
          "type" => "webhook",
          "url" => "https://example.com/webhooks/postgres",
          "timeout_seconds" => 5
        },
        label: "destinations[0]"
      )

      assert_instance_of WebhookSink, sink
      assert_equal "primary_webhook", sink.name
    end

    def test_unknown_destination_type_fails_clearly
      error = assert_raises(ConfigurationError) do
        Destinations::Registry.build({ "name" => "queue", "type" => "kafka" }, label: "destinations[0]")
      end

      assert_match(/unknown destination adapter: kafka/, error.message)
    end

    CustomAdapter = Class.new(Destinations::Adapter)
  end
end
