# frozen_string_literal: true

module Mammoth
  module Destinations
    # Built-in webhook destination adapter.
    class WebhookAdapter < Adapter
      class << self
        # @return [String] adapter type name
        def adapter_type
          "webhook"
        end

        # Build a webhook sink from destination configuration.
        #
        # @param destination [Hash] destination configuration
        # @param label [String] config path label for errors
        # @return [Mammoth::WebhookSink]
        def build(destination, label:)
          WebhookSink.from_destination_config(destination, label: label)
        end

        # @return [Hash] JSON-friendly capabilities
        def capabilities
          { type: adapter_type, delivery_units: %w[event transaction], signing: true, header_env: true }
        end
      end
    end
  end
end
