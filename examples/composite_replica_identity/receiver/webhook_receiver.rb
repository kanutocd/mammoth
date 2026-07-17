# frozen_string_literal: true

require "json"
require "webrick"

EXPECTED_OPERATIONS = %w[insert update delete].freeze
EXPECTED_IDENTITY = { "tenant_id" => 9, "member_uuid" => "member-1" }.freeze

server = WEBrick::HTTPServer.new(Port: 9292, BindAddress: "0.0.0.0")

server.mount_proc "/webhook" do |request, response|
  payload = JSON.parse(request.body)
  events = payload.fetch("events")
  operations = events.map { |event| event.fetch("operation") }
  identities = events.map { |event| event.fetch("identity") }

  raise "expected a committed transaction" unless payload.fetch("type") == "transaction.committed"
  raise "expected operations #{EXPECTED_OPERATIONS.inspect}, got #{operations.inspect}" unless operations == EXPECTED_OPERATIONS
  raise "composite replica identity was not preserved" unless identities.all? { |identity| identity == EXPECTED_IDENTITY }

  puts "payload type: #{payload.fetch("type")}"
  puts "event_count: #{payload.fetch("event_count")}"
  events.each_with_index do |event, index|
    puts "event[#{index}]: #{event.fetch("operation")} #{event.fetch("entity")} identity=#{event.fetch("identity").inspect}"
  end
  puts "composite identity verified for INSERT, UPDATE, and DELETE"
  $stdout.flush

  response.status = 200
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(status: "ok")
rescue KeyError, JSON::ParserError => e
  response.status = 400
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(error: e.message)
rescue RuntimeError => e
  warn e.message
  response.status = 422
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(error: e.message)
end

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }
server.start
