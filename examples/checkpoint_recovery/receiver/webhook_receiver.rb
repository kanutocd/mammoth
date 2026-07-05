# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require "webrick"

$stdout.sync = true
$stderr.sync = true

DATA_DIR = ENV.fetch("RECEIVER_DATA_DIR", "/data")
LOG_PATH = File.join(DATA_DIR, "received.log")

FileUtils.mkdir_p(DATA_DIR)
File.write(LOG_PATH, "") unless File.exist?(LOG_PATH)

class CheckpointRecoveryServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_POST(request, response)
    payload = JSON.parse(request.body)
    event = payload.fetch("events").first
    data = event.fetch("data")
    order_key = data.fetch("order_key")
    transaction_id = payload["transaction_id"]
    source_position = payload["source_position"]
    timestamp = Time.now.utc.iso8601(6)

    line = [timestamp, transaction_id, source_position, order_key].join(" ")
    File.open(LOG_PATH, "a") { |file| file.puts(line) }

    delivered = File.readlines(LOG_PATH, chomp: true).map { |entry| entry.split.last }
    puts "received transaction_id=#{transaction_id} source_position=#{source_position} order_key=#{order_key} delivered=#{delivered.inspect}"
    $stdout.flush

    response.status = 200
    response["Content-Type"] = "application/json"
    response.body = JSON.generate(ok: true, delivered: delivered)
  rescue StandardError => e
    warn "receiver error: #{e.class}: #{e.message}"
    response.status = 500
    response["Content-Type"] = "application/json"
    response.body = JSON.generate(ok: false, error: e.message)
  end
end

server = WEBrick::HTTPServer.new(
  BindAddress: "0.0.0.0",
  Port: Integer(ENV.fetch("PORT", "9292")),
  AccessLog: [],
  Logger: WEBrick::Log.new($stdout, WEBrick::Log::INFO)
)

server.mount "/webhook", CheckpointRecoveryServlet
puts "checkpoint recovery receiver listening on /webhook port=#{server.config[:Port]} data_dir=#{DATA_DIR}"
trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }
server.start
