# frozen_string_literal: true

require "json"
require "webrick"

server = WEBrick::HTTPServer.new(Port: 9292, BindAddress: "0.0.0.0")

server.mount_proc "/webhook" do |request, response|
  payload = JSON.parse(request.body)
  puts "rejecting #{payload.fetch("event_id")} #{payload.fetch("operation")} #{payload.fetch("entity")}"
  $stdout.flush

  response.status = 500
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(status: "failed", reason: "intentional demo failure")
rescue JSON::ParserError => e
  response.status = 400
  response.body = JSON.generate(error: e.message)
end

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }
server.start
