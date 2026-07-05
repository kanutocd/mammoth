# frozen_string_literal: true

# Benchmark Mammoth::WebhookSink against a local WEBrick receiver. This covers
# JSON serialization, HTTP POST overhead, static headers, env-backed
# Authorization, and optional HMAC signing.

require_relative "support"

require "mammoth/webhook_sink"
require "mammoth/event_serializer"
require "mammoth/transaction_envelope_serializer"

module MammothBenchmarks
  class WebhookDeliveryBenchmark
    attr_reader :requests, :latency_ms, :delivery_unit, :auth, :signing

    def initialize(
      requests: Helpers.env_integer("MAMMOTH_BENCH_REQUESTS", 1_000),
      latency_ms: Helpers.env_float("MAMMOTH_BENCH_LATENCY_MS", 0.0),
      delivery_unit: ENV.fetch("MAMMOTH_BENCH_DELIVERY_UNIT", "transaction"),
      auth: Helpers.env_boolean("MAMMOTH_BENCH_AUTH", true),
      signing: Helpers.env_boolean("MAMMOTH_BENCH_SIGNING", true)
    )
      @requests = requests
      @latency_ms = latency_ms
      @delivery_unit = delivery_unit
      @auth = auth
      @signing = signing
    end

    def run
      puts "Mammoth webhook delivery benchmark"
      puts "requests=#{requests} delivery_unit=#{delivery_unit} receiver_latency_ms=#{latency_ms} " \
           "auth=#{auth} signing=#{signing}"
      puts

      with_receiver do |url, received|
        sink = build_sink(url)
        work_items = build_work_items
        started_at = Helpers.monotonic_time
        work_items.each { |work| deliver(sink, work) }
        elapsed = Helpers.monotonic_time - started_at
        result = build_result(elapsed, received)
        print_result(result)
        Helpers.maybe_print_json([result])
        [result]
      end
    end

    private

    def with_receiver
      receiver = LocalHTTPReceiver.new(latency_seconds: latency_ms / 1_000.0)
      yield receiver.url, receiver
    ensure
      receiver&.shutdown
    end

    def build_sink(url)
      ENV["MAMMOTH_BENCH_WEBHOOK_AUTHORIZATION"] = "Bearer benchmark-token" if auth
      ENV["MAMMOTH_BENCH_WEBHOOK_SIGNING_SECRET"] = "benchmark-signing-secret" if signing

      Mammoth::WebhookSink.new(
        name: "benchmark_webhook",
        url: url,
        timeout_seconds: 5,
        headers: auth ? { "Authorization" => ENV.fetch("MAMMOTH_BENCH_WEBHOOK_AUTHORIZATION") } : {},
        signing: signing_config
      )
    end

    def signing_config
      return unless signing

      {
        secret: ENV.fetch("MAMMOTH_BENCH_WEBHOOK_SIGNING_SECRET"),
        signature_header: "X-Mammoth-Signature",
        timestamp_header: "X-Mammoth-Timestamp"
      }
    end

    def build_work_items
      if delivery_unit == "event"
        Helpers.build_events(requests)
      else
        Helpers.build_envelopes(requests, events_per_transaction: events_per_transaction)
      end
    end

    def events_per_transaction
      Helpers.env_integer("MAMMOTH_BENCH_EVENTS_PER_TRANSACTION", 4)
    end

    def deliver(sink, work)
      delivery_unit == "event" ? sink.deliver(work) : sink.deliver_transaction(work)
    end

    def build_result(elapsed, received)
      {
        requests: requests,
        delivery_unit: delivery_unit,
        receiver_latency_ms: latency_ms,
        auth: auth,
        signing: signing,
        received_requests: received.snapshot.fetch(:requests),
        received_bytes: received.snapshot.fetch(:bytes),
        elapsed_seconds: elapsed.round(6),
        requests_per_second: Helpers.rate(requests, elapsed)
      }
    end

    def print_result(result)
      Helpers.print_table(
        %w[requests unit latency_ms auth signing req/sec elapsed_s bytes],
        [result]
      ) do |row|
        [
          row.fetch(:requests),
          row.fetch(:delivery_unit),
          row.fetch(:receiver_latency_ms),
          row.fetch(:auth),
          row.fetch(:signing),
          row.fetch(:requests_per_second),
          row.fetch(:elapsed_seconds),
          row.fetch(:received_bytes)
        ]
      end
    end
  end
end

MammothBenchmarks::WebhookDeliveryBenchmark.new.run if $PROGRAM_NAME == __FILE__
