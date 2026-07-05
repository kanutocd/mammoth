# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "socket"
require "tmpdir"
require "time"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

module MammothBenchmarks
  SyntheticEvent = Data.define(:event_id, :operation, :namespace, :entity, :identity, :source_position, :metadata) do
    def to_h
      {
        "event_id" => event_id,
        "source" => "postgresql",
        "operation" => operation,
        "namespace" => namespace,
        "entity" => entity,
        "identity" => identity,
        "source_position" => source_position,
        "metadata" => metadata
      }
    end
  end

  SyntheticEnvelope = Data.define(:event_id, :transaction_id, :source_position, :commit_lsn, :committed_at, :events, :metadata) do
    def to_h
      {
        "event_id" => event_id,
        "transaction_id" => transaction_id,
        "source_position" => source_position,
        "commit_lsn" => commit_lsn,
        "committed_at" => committed_at,
        "events" => events,
        "metadata" => metadata
      }
    end
  end

  module Helpers
    module_function

    def env_integer(name, default)
      value = ENV[name]
      return default if value.nil? || value.empty?

      Integer(value, 10)
    end

    def env_float(name, default)
      value = ENV[name]
      return default if value.nil? || value.empty?

      Float(value)
    end

    def env_boolean(name, default)
      value = ENV[name]
      return default if value.nil? || value.empty?

      %w[1 true yes on].include?(value.downcase)
    end

    def env_list(name, default, coercer: ->(entry) { entry })
      value = ENV[name]
      return default if value.nil? || value.empty?

      value.split(",").map { |entry| coercer.call(entry.strip) }
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def rate(count, elapsed)
      return 0.0 if elapsed.zero?

      (count / elapsed).round(2)
    end

    def average(values)
      return 0.0 if values.empty?

      values.sum / values.length.to_f
    end

    def percentile(values, quantile)
      return 0.0 if values.empty?

      sorted = values.sort
      index = [(sorted.length * quantile).ceil - 1, 0].max
      sorted.fetch(index)
    end

    def print_table(headers, results, &row_builder)
      widths = headers.map(&:length)
      rows = results.map { |result| row_builder.call(result) }
      rows.each do |row|
        row.each_with_index { |value, index| widths[index] = [widths[index], value.to_s.length].max }
      end

      puts headers.each_with_index.map { |header, index| header.rjust(widths[index]) }.join(" ")
      puts widths.map { |width| "-" * width }.join(" ")
      rows.each { |row| puts row.each_with_index.map { |value, index| value.to_s.rjust(widths[index]) }.join(" ") }
    end

    def maybe_print_json(results)
      return unless ENV["MAMMOTH_BENCH_JSON"]

      puts
      puts JSON.pretty_generate(results)
    end

    def build_events(count, prefix: "event", source_position: nil)
      Array.new(count) do |index|
        position = source_position || (10_000 + index).to_s
        SyntheticEvent.new(
          "#{prefix}-#{index + 1}",
          index.zero? ? "insert" : "update",
          "public",
          "orders",
          { "id" => index + 1 },
          position,
          { "benchmark" => true, "event_index" => index }
        )
      end
    end

    def build_envelopes(count, events_per_transaction:, prefix: "tx")
      Array.new(count) do |index|
        position = (10_000 + index).to_s
        events = build_events(events_per_transaction, prefix: "#{prefix}-#{index + 1}", source_position: position)
        SyntheticEnvelope.new(
          SecureRandom.uuid,
          "#{prefix}-#{index + 1}",
          position,
          position,
          Time.now.utc.iso8601,
          events,
          { "benchmark" => true }
        )
      end
    end

    def with_temp_sqlite
      Dir.mktmpdir("mammoth-bench-") do |dir|
        yield File.join(dir, "mammoth.db")
      end
    end
  end

  class LocalHTTPReceiver
    attr_reader :latency_seconds, :requests, :bytes, :server, :thread

    def initialize(latency_seconds:)
      @latency_seconds = latency_seconds
      @requests = 0
      @bytes = 0
      @server = TCPServer.new("127.0.0.1", 0)
      @thread = Thread.new { serve }
    end

    def url
      "http://127.0.0.1:#{server.addr.fetch(1)}/webhook"
    end

    def snapshot
      { requests: requests, bytes: bytes }
    end

    def shutdown
      server.close
      thread.join
    rescue IOError
      thread.join
    end

    private

    def serve
      loop do
        socket = server.accept
        handle(socket)
      rescue IOError
        break
      end
    end

    def handle(socket)
      headers = read_headers(socket)
      body = read_body(socket, content_length(headers))
      sleep(latency_seconds) if latency_seconds.positive?
      @requests += 1
      @bytes += body.bytesize
      socket.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
    ensure
      socket&.close
    end

    def read_headers(socket)
      headers = {}
      request_line = socket.gets
      return headers unless request_line

      while (line = socket.gets)
        line = line.chomp
        break if line.empty?

        key, value = line.split(":", 2)
        headers[key.downcase] = value.to_s.strip if key
      end
      headers
    end

    def read_body(socket, length)
      return "" unless length.positive?

      socket.read(length).to_s
    end

    def content_length(headers)
      Integer(headers.fetch("content-length", "0"), 10)
    end
  end
end
