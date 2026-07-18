# frozen_string_literal: true

require "net/http"
require "time"
require "uri"

$stdout.sync = true

# Produces a readable sequence of order transactions across multiple Prometheus
# scrape intervals so the provisioned Grafana dashboard has useful demo data.
class MonitoringSeeder
  def initialize
    @demo_app = URI(ENV.fetch("DEMO_APP_URL", "http://localhost:3000"))
    @interval = Float(ENV.fetch("SEED_INTERVAL_SECONDS", "4"))
    @run_id = Time.now.utc.strftime("%Y%m%d%H%M%S")
  end

  def call
    phase("capturing a Prometheus baseline") { pause(6) }
    pending = seed_pending_demand
    paid = seed_payments
    seed_fulfillment(paid)
    seed_deletions(pending)
    seed_reversals

    puts "Monitoring seed complete. Open http://localhost:3001/d/mammoth-quickstart"
  end

  private

  def seed_pending_demand
    phase("creating pending demand") { create_orders("pending", [24.50, 49.99, 79.00]) }
  end

  def seed_payments
    phase("capturing customer payments") do
      create_orders("paid", [18.75, 42.50, 88.00, 129.00]).each { |id| action(id, "pay") }
    end
  end

  def seed_fulfillment(paid)
    phase("moving paid orders through fulfillment") do
      paid.first(2).each { |id| action(id, "status", status: "shipped") }
      action(paid.first, "status", status: "received")
    end
  end

  def seed_deletions(pending)
    phase("showing pending cancellation as DELETE") do
      pending.last(2).each { |id| action(id, "delete") }
    end
  end

  def seed_reversals
    phase("showing paid cancellation as an accounting reversal") do
      create_orders("reversal", [64.25, 155.40]).each do |id|
        action(id, "pay")
        action(id, "cancel")
      end
    end
  end

  def phase(description)
    puts "Monitoring seed: #{description}..."
    result = yield
    pause
    result
  end

  def create_orders(label, totals)
    totals.each_with_index.map { |total, index| create_order("#{label}-#{index + 1}", total) }
  end

  def create_order(label, total)
    response = post(
      @demo_app,
      "/orders",
      customer_email: order_email(label),
      total: format("%.2f", total)
    )
    order_id = response["location"].to_s[/#order-(\d+)\z/, 1]
    raise "Create order response did not identify the new order" unless order_id

    order_id
  end

  def order_email(label)
    "#{label}-#{@run_id}@example.com"
  end

  def action(order_id, endpoint, params = {})
    post(@demo_app, "/orders/#{order_id}/#{endpoint}", params)
  end

  def post(base, path, params)
    request = Net::HTTP::Post.new(path)
    request.set_form_data(params)
    response = request(base, request)
    raise "POST #{path} returned HTTP #{response.code}" unless %w[200 303].include?(response.code)

    response
  end

  def request(base, request)
    Net::HTTP.start(base.host, base.port, open_timeout: 3, read_timeout: 10) do |http|
      http.request(request)
    end
  end

  def pause(seconds = @interval)
    sleep(seconds) if seconds.positive?
  end
end

MonitoringSeeder.new.call if $PROGRAM_NAME == __FILE__
