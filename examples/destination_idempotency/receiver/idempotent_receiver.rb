# frozen_string_literal: true

require "json"
require "sqlite3"
require "webrick"

DATABASE_PATH = ENV.fetch("RECEIVER_DATABASE", "/data/receiver.db")

def connect
  database = SQLite3::Database.new(DATABASE_PATH)
  database.busy_timeout = 5_000
  database.results_as_hash = true
  database
end

def bootstrap
  connect.execute_batch(<<~SQL)
    PRAGMA journal_mode = WAL;

    CREATE TABLE IF NOT EXISTS delivery_attempts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_id TEXT NOT NULL,
      received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS applied_order_events (
      event_id TEXT PRIMARY KEY,
      order_id INTEGER NOT NULL,
      status TEXT NOT NULL,
      applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
  SQL
end

def apply_once(event)
  database = connect
  data = event.fetch("data")

  database.transaction(:immediate) do
    database.execute("INSERT INTO delivery_attempts (event_id) VALUES (?)", event.fetch("event_id"))
    database.execute(
      "INSERT OR IGNORE INTO applied_order_events (event_id, order_id, status) VALUES (?, ?, ?)",
      [event.fetch("event_id"), data.fetch("id"), data.fetch("status")]
    )
    database.changes == 1
  end
ensure
  database&.close
end

def state
  database = connect
  {
    delivery_attempts: database.get_first_value("SELECT COUNT(*) FROM delivery_attempts"),
    applied_side_effects: database.get_first_value("SELECT COUNT(*) FROM applied_order_events"),
    event_ids: database.execute("SELECT event_id FROM applied_order_events ORDER BY event_id").map { |row| row["event_id"] }
  }
ensure
  database&.close
end

bootstrap
server = WEBrick::HTTPServer.new(Port: 9292, BindAddress: "0.0.0.0")

server.mount_proc "/webhook" do |request, response|
  event = JSON.parse(request.body)
  applied = apply_once(event)
  puts "#{applied ? "applied" : "duplicate"} event_id=#{event.fetch("event_id")}"
  $stdout.flush

  response.status = 200
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(status: applied ? "applied" : "duplicate")
rescue JSON::ParserError, KeyError => e
  response.status = 400
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(error: e.message)
end

server.mount_proc "/state" do |_request, response|
  response.status = 200
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(state)
end

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }
server.start
