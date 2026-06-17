# frozen_string_literal: true

require "json"
require "net/http"
require "socket"
require "uri"

module Mammoth
  # Delivers normalized Mammoth events to a webhook endpoint.
  class WebhookSink
    # HTTP status range treated as successful webhook delivery.
    SUCCESS_RANGE = 200..299

    attr_reader :name, :url, :timeout_seconds

    # @param name [String] destination name
    # @param url [String] webhook endpoint URL
    # @param timeout_seconds [Integer] HTTP open/read timeout in seconds
    def initialize(name:, url:, timeout_seconds: 5)
      @name = name
      @url = URI(url)
      @timeout_seconds = timeout_seconds
    end

    # Build a sink from Mammoth configuration.
    #
    # @param config [Mammoth::Configuration] loaded configuration
    # @return [Mammoth::WebhookSink]
    def self.from_config(config)
      new(
        name: config.dig("webhook", "name"),
        url: config.dig("webhook", "url"),
        timeout_seconds: config.dig("webhook", "timeout_seconds")
      )
    end

    # Deliver an event to the webhook endpoint.
    #
    # @param event [Hash, #to_h] normalized event
    # @return [Hash] delivery result
    # @raise [Mammoth::DeliveryError] when delivery fails
    def deliver(event)
      deliver_payload(EventSerializer.call(event))
    end

    # Deliver a transaction envelope to the webhook endpoint.
    #
    # @param envelope [#events, #transaction_id] CDC transaction envelope
    # @return [Hash] delivery result
    # @raise [Mammoth::DeliveryError] when delivery fails
    def deliver_transaction(envelope)
      deliver_payload(TransactionEnvelopeSerializer.call(envelope))
    end

    private

    def deliver_payload(payload)
      response = perform_request(payload)
      return delivery_result(payload, response) if SUCCESS_RANGE.cover?(response.code.to_i)

      raise DeliveryError, "webhook #{name} returned HTTP #{response.code}"
    rescue Timeout::Error, SystemCallError, SocketError, JSON::GeneratorError => e
      raise DeliveryError, "webhook #{name} delivery failed: #{e.message}"
    end

    def perform_request(payload)
      Net::HTTP.start(url.host, url.port, use_ssl: url.scheme == "https", open_timeout: timeout_seconds,
                                          read_timeout: timeout_seconds) do |http|
        http.request(build_request(payload))
      end
    end

    def build_request(payload)
      Net::HTTP::Post.new(url.request_uri).tap do |request|
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
      end
    end

    def delivery_result(payload, response)
      {
        event_id: payload.fetch("event_id"),
        payload_type: payload["type"] || "event",
        destination: name,
        status: "delivered",
        http_status: response.code.to_i
      }
    end
  end
end
