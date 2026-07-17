# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "socket"
require "time"
require "uri"

module Mammoth
  # Delivers normalized Mammoth events to a webhook endpoint.
  class WebhookSink
    # HTTP status range treated as successful webhook delivery.
    SUCCESS_RANGE = 200..299

    # Supported webhook signing algorithm.
    SIGNING_ALGORITHM = "hmac_sha256"
    # Prefix added to generated webhook signatures.
    SIGNATURE_PREFIX = "sha256="

    attr_reader :name, :url, :timeout_seconds, :headers, :signing

    # @param name [String] destination name
    # @param url [String] webhook endpoint URL
    # @param timeout_seconds [Integer] HTTP open/read timeout in seconds
    # @param headers [Hash] static HTTP headers applied to every request
    # @param signing [Hash, nil] HMAC signing configuration
    def initialize(name:, url:, timeout_seconds: 5, headers: {}, signing: nil)
      @name = name
      @url = URI(url)
      @timeout_seconds = timeout_seconds
      @headers = headers.transform_keys(&:to_s)
      @signing = signing
    end

    class << self
      # Build a sink from Mammoth configuration.
      #
      # @param config [Mammoth::Configuration] loaded configuration
      # @return [Mammoth::WebhookSink]
      def from_config(config)
        from_destination_config(config.data["webhook"], label: "webhook")
      end

      # Build a sink from one destination configuration entry.
      #
      # @param destination [Hash] destination configuration
      # @param label [String] configuration path used in error messages
      # @return [Mammoth::WebhookSink]
      def from_destination_config(destination, label: "destination")
        new(
          name: destination.fetch("name"),
          url: destination.fetch("url"),
          timeout_seconds: destination.fetch("timeout_seconds"),
          headers: configured_headers(destination, label: label),
          signing: configured_signing(destination, label: label)
        )
      end

      private

      def configured_headers(destination, label:)
        static_headers = destination["headers"] || {}
        env_headers = destination["header_env"] || {}

        static_headers.merge(resolve_env_headers(env_headers, label: label))
      end

      def resolve_env_headers(env_headers, label:)
        env_headers.each_with_object(Hash.new) do |(header, env_name), resolved| # rubocop:disable Style/EmptyLiteral
          resolved[header] = ENV.fetch(env_name) do
            raise ConfigurationError, "#{label}.header_env.#{header} references missing environment variable #{env_name}"
          end
        end
      end

      def configured_signing(destination, label:)
        signing = destination["signing"]
        return unless signing

        algorithm = signing.fetch("algorithm", SIGNING_ALGORITHM)
        raise ConfigurationError, "#{label}.signing.algorithm must be #{SIGNING_ALGORITHM}" unless algorithm == SIGNING_ALGORITHM

        secret_env = signing.fetch("secret_env")
        {
          secret: ENV.fetch(secret_env) do
            raise ConfigurationError, "#{label}.signing.secret_env references missing environment variable #{secret_env}"
          end,
          signature_header: signing.fetch("signature_header", "X-Mammoth-Signature"),
          timestamp_header: signing.fetch("timestamp_header", "X-Mammoth-Timestamp")
        }
      end
    end

    # Deliver an event to the webhook endpoint.
    #
    # @param event [CDC::Core::ChangeEvent] normalized event
    # @return [Hash] delivery result
    # @raise [Mammoth::DeliveryError] when delivery fails
    def deliver(event)
      deliver_payload(EventSerializer.call(event))
    end

    # Deliver a transaction envelope to the webhook endpoint.
    #
    # @param envelope [CDC::Core::TransactionEnvelope] CDC transaction envelope
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
      body = JSON.generate(payload)
      Net::HTTP::Post.new(url.request_uri).tap do |request|
        request["Content-Type"] = "application/json"
        headers.each { |header, value| request[header] = value }
        apply_signature_headers(request, body)
        request.body = body
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

    def apply_signature_headers(request, body)
      return unless signing

      timestamp = Time.now.utc.iso8601
      request[signing.fetch(:timestamp_header)] = timestamp
      request[signing.fetch(:signature_header)] = signed_body(timestamp, body)
    end

    def signed_body(timestamp, body)
      digest = OpenSSL::HMAC.hexdigest("SHA256", signing.fetch(:secret), "#{timestamp}.#{body}")
      "#{SIGNATURE_PREFIX}#{digest}"
    end
  end
end
