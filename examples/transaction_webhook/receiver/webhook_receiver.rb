# frozen_string_literal: true

require "json"
require "webrick"

server = WEBrick::HTTPServer.new(Port: 9292, BindAddress: "0.0.0.0")

server.mount_proc "/webhook" do |request, response|
  payload = JSON.parse(request.body)

  type = payload.fetch("type", "event")
  puts "payload type: #{type}"

  if type == "transaction.committed"
    puts "transaction_id: #{payload.fetch("transaction_id")}"
    puts "source_position: #{payload.fetch("source_position")}"
    puts "event_count: #{payload.fetch("event_count")}"
    payload.fetch("events").each_with_index do |event, index|
      puts "event[#{index}]: #{event.fetch("operation")} #{event.fetch("entity")} #{event.fetch("identity").inspect}"
    end
  else
    puts "event_id: #{payload.fetch("event_id")}"
    puts "operation: #{payload.fetch("operation")}"
    puts "entity: #{payload.fetch("entity")}"
  end

  $stdout.flush

  response.status = 200
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(status: "ok")
rescue KeyError, JSON::ParserError => e
  response.status = 400
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(error: e.message)
end

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }
server.start
