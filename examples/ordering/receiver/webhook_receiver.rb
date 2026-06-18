# frozen_string_literal: true

require "json"
require "time"
require "webrick"

server = WEBrick::HTTPServer.new(Port: 9292, BindAddress: "0.0.0.0")

# Make ordering differences visible.
#
# Transaction A is intentionally slow. With preserve_order: true, B and C wait
# behind A. With preserve_order: false, B and C can complete before A.
LATENCY_BY_ORDER_KEY = {
  "A" => 3.0,
  "B" => 0.1,
  "C" => 0.1
}.freeze

$received = []

server.mount_proc "/webhook" do |request, response|
  payload = JSON.parse(request.body)
  event = payload.fetch("events").first
  data = event.fetch("data")
  order_key = data.fetch("order_key")
  latency = LATENCY_BY_ORDER_KEY.fetch(order_key, 0.0)

  started_at = Time.now.utc
  sleep latency
  completed_at = Time.now.utc

  $received << order_key

  puts "received transaction_id=#{payload.fetch("transaction_id")} order_key=#{order_key} latency=#{latency}s started_at=#{started_at.iso8601(6)} completed_at=#{completed_at.iso8601(6)} completion_order=#{$received.join}"
  $stdout.flush

  response.status = 200
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(status: "ok", order_key: order_key, completion_order: $received)
rescue KeyError, JSON::ParserError => e
  response.status = 400
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(error: e.message)
end

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }
server.start
