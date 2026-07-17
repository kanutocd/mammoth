# frozen_string_literal: true

require "json"
require "webrick"

def accepted_shape(event)
  data = event.fetch("data")
  status = data.fetch("status")

  raise "expected orders INSERT" unless event.fetch("entity") == "orders" && event.fetch("operation") == "insert"

  case status
  when "before_migration"
    raise "v1 event unexpectedly contains currency" if data.key?("currency")

    ["v1", status, data.keys]
  when "after_migration"
    raise "v2 event did not contain currency=USD" unless data["currency"] == "USD"

    ["v2", status, data.keys]
  else
    raise "unexpected order status #{status.inspect}"
  end
end

server = WEBrick::HTTPServer.new(Port: 9292, BindAddress: "0.0.0.0")

server.mount_proc "/webhook" do |request, response|
  shape, status, fields = accepted_shape(JSON.parse(request.body))

  puts "accepted #{shape} event status=#{status} fields=#{fields.sort.join(",")}"
  $stdout.flush

  response.status = 200
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(status: "ok", accepted_shape: shape)
rescue JSON::ParserError, KeyError => e
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
