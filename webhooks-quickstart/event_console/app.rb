# frozen_string_literal: true

require "erb"
require "json"
require "openssl"
require "rack"
require "rackup"
require "securerandom"
require "time"
require "webrick"

# Signed webhook receiver and browser-based delivery attempt inspector.
class EventConsole
  ROOT = __dir__
  MAX_EVENTS = 250
  TEMPLATE_ROOT = File.join(ROOT, "views")
  ASSETS = {
    "/assets/app.css" => [File.join(ROOT, "public", "app.css"), "text/css; charset=utf-8"],
    "/assets/app.js" => [File.join(ROOT, "public", "app.js"), "application/javascript; charset=utf-8"],
    "/assets/vendor/renderjson.js" => [
      File.join(ROOT, "public", "vendor", "renderjson.js"),
      "application/javascript; charset=utf-8"
    ]
  }.freeze

  def initialize
    @mutex = Mutex.new
    @data_dir = ENV.fetch("DATA_DIR", "/data")
    Dir.mkdir(@data_dir) unless Dir.exist?(@data_dir)
    @events_file = File.join(@data_dir, "events.jsonl")
    @failure_file = File.join(@data_dir, "failures-enabled")
    @authorization = ENV.fetch("WEBHOOK_AUTHORIZATION")
    @signing_secret = ENV.fetch("WEBHOOK_SIGNING_SECRET")
  end

  def call(env)
    request = Rack::Request.new(env)
    return get(request.path) if request.get?
    return post(request) if request.post?

    not_found
  rescue JSON::ParserError
    json(400, error: "invalid_json")
  rescue StandardError => e
    warn("event-console error: #{e.class}: #{e.message}")
    json(500, error: "internal_error")
  end

  private

  def get(path)
    return json(200, status: "ok") if path == "/health"
    return static_asset(path) if ASSETS.key?(path)
    return render_index if path == "/"
    return events_json if path == "/api/events"

    not_found
  end

  def post(request)
    return toggle_failures(request) if request.path == "/api/failures"
    return clear_events if request.path == "/api/events/clear"
    return receive_webhook(request) if request.path == "/webhooks/mammoth"

    not_found
  end

  def receive_webhook(request)
    body = request.body.read
    return json(401, error: "invalid_authorization") unless authorized?(request)
    return json(401, error: "invalid_signature") unless valid_signature?(request, body)

    payload = body.empty? ? {} : JSON.parse(body)
    response_status = failures_enabled? ? 500 : 200
    event = {
      id: SecureRandom.uuid,
      received_at: Time.now.utc.iso8601(6),
      delivery_key: delivery_key(payload),
      request_id: request.get_header("HTTP_X_REQUEST_ID"),
      user_agent: request.user_agent,
      signature_verified: true,
      response_status: response_status,
      outcome: response_status == 200 ? "accepted" : "simulated_failure",
      payload: payload
    }
    append_event(event)

    return json(500, accepted: false, simulated_failure: true, event_id: event[:id]) if response_status == 500

    json(200, accepted: true, event_id: event[:id])
  end

  def authorized?(request)
    secure_compare(request.get_header("HTTP_AUTHORIZATION").to_s, @authorization)
  end

  def valid_signature?(request, body)
    timestamp = request.get_header("HTTP_X_MAMMOTH_TIMESTAMP").to_s
    signature = request.get_header("HTTP_X_MAMMOTH_SIGNATURE").to_s
    return false if timestamp.empty? || signature.empty?

    signed_at = Time.iso8601(timestamp)
    return false if (Time.now.utc - signed_at).abs > 300

    digest = OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, "#{timestamp}.#{body}")
    secure_compare(signature, "sha256=#{digest}")
  rescue ArgumentError
    false
  end

  def secure_compare(left, right)
    return false unless left.bytesize == right.bytesize

    Rack::Utils.secure_compare(left, right)
  end

  def delivery_key(payload)
    payload["event_id"] || payload["transaction_id"] || SecureRandom.uuid
  end

  def render_index
    html(200, render_template("index"))
  end

  def events_json
    json(200, events: read_events.reverse, failures_enabled: failures_enabled?)
  end

  def toggle_failures(request)
    enabled = JSON.parse(request.body.read).fetch("enabled")
    if enabled
      File.write(@failure_file, "enabled\n")
    elsif File.exist?(@failure_file)
      File.delete(@failure_file)
    end
    json(200, failures_enabled: failures_enabled?)
  end

  def clear_events
    @mutex.synchronize { File.write(@events_file, "") }
    json(200, cleared: true)
  end

  def append_event(event)
    @mutex.synchronize do
      existing = read_event_lines
      event[:attempt] = existing.count { |item| item[:delivery_key] == event[:delivery_key] } + 1
      File.open(@events_file, "a") { |file| file.puts(JSON.generate(event)) }
      lines = File.readlines(@events_file)
      File.write(@events_file, lines.last(MAX_EVENTS).join) if lines.length > MAX_EVENTS
    end
  end

  def read_events
    return [] unless File.exist?(@events_file)

    @mutex.synchronize { read_event_lines }
  end

  def read_event_lines
    return [] unless File.exist?(@events_file)

    File.readlines(@events_file).filter_map { |line| JSON.parse(line, symbolize_names: true) unless line.strip.empty? }
  end

  def render_template(name)
    ERB.new(File.read(File.join(TEMPLATE_ROOT, "#{name}.erb"))).result(binding)
  end

  def static_asset(path)
    file, content_type = ASSETS.fetch(path)
    [200, { "content-type" => content_type, "cache-control" => "no-cache" }, [File.binread(file)]]
  end

  def failures_enabled? = File.exist?(@failure_file)
  def html(status, body) = [status, { "content-type" => "text/html; charset=utf-8" }, [body]]
  def json(status, object) = [status, { "content-type" => "application/json" }, [JSON.generate(object)]]
  def not_found = json(404, error: "not_found")
end

if $PROGRAM_NAME == __FILE__
  Rackup::Handler::WEBrick.run(
    EventConsole.new,
    Host: "0.0.0.0",
    Port: Integer(ENV.fetch("PORT", "4000")),
    AccessLog: [],
    Logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO)
  )
end
