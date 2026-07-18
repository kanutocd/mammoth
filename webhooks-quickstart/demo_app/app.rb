# frozen_string_literal: true

require "cgi"
require "erb"
require "json"
require "pg"
require "rack"
require "rackup"
require "webrick"

# Minimal order application that demonstrates ordinary PostgreSQL writes.
class DemoStore
  ROOT = __dir__
  ORDER_ACTIONS = {
    "pending" => [
      { label: "Pay", endpoint: "status", status: "paid" },
      {
        label: "Cancel",
        endpoint: "delete",
        confirmation: "Cancel this pending order?\n\n" \
                      "This permanently deletes the order from PostgreSQL. " \
                      "Mammoth will emit a DELETE webhook, and the order cannot be restored."
      }
    ],
    "paid" => [
      { label: "Ship", endpoint: "status", status: "shipped" },
      { label: "Cancel", endpoint: "status", status: "cancelled" }
    ],
    "cancelled" => [],
    "shipped" => [
      { label: "Receive", endpoint: "status", status: "received" }
    ],
    "received" => []
  }.freeze
  STATUSES = ORDER_ACTIONS.keys.freeze
  TEMPLATE_ROOT = File.join(ROOT, "views")
  ASSETS = {
    "/assets/app.css" => [File.join(ROOT, "public", "app.css"), "text/css; charset=utf-8"],
    "/assets/app.js" => [File.join(ROOT, "public", "app.js"), "application/javascript; charset=utf-8"]
  }.freeze

  def call(env)
    request = Rack::Request.new(env)
    return get(request.path) if request.get?
    return post(request) if request.post?

    redirect("/")
  rescue PG::Error => e
    render_error(500, "Database error", e.message)
  end

  private

  def get(path)
    return json(200, status: "ok") if path == "/health"
    return static_asset(path) if ASSETS.key?(path)
    return render_index if path == "/"

    redirect("/")
  end

  def post(request)
    return create_order(request) if request.path == "/orders"
    return update_status(request) if request.path.match?(%r{\A/orders/\d+/status\z})
    return delete_order(request) if request.path.match?(%r{\A/orders/\d+/delete\z})

    redirect("/")
  end

  def render_index
    orders = connection { |db| db.exec("SELECT * FROM orders ORDER BY id DESC") }.to_a
    html(200, page("Demo Store", render_template("index", orders: orders, order_actions: ORDER_ACTIONS)))
  end

  def create_order(request)
    cents = (Float(request.params.fetch("total")) * 100).round
    email = request.params.fetch("customer_email").strip
    order = connection do |db|
      db.exec_params(
        "INSERT INTO orders (customer_email, total_cents) VALUES ($1, $2) RETURNING id",
        [email, cents]
      ).first
    end
    redirect("/#order-#{order.fetch("id")}")
  rescue ArgumentError, KeyError
    render_error(422, "Invalid order", "Enter a valid email and positive total.")
  end

  def update_status(request)
    id = request.path.split("/")[2]
    status = request.params.fetch("status")
    return render_error(422, "Invalid status", "Unknown order status.") unless STATUSES.include?(status)

    connection { |db| db.exec_params("UPDATE orders SET status = $1 WHERE id = $2", [status, id]) }
    redirect("/")
  end

  def delete_order(request)
    id = request.path.split("/")[2]
    result = connection { |db| db.exec_params("DELETE FROM orders WHERE id = $1 AND status = 'pending'", [id]) }
    return render_error(409, "Cannot cancel order", "Only pending orders can be deleted.") if result.cmd_tuples.zero?

    redirect("/")
  end

  def connection
    db = PG.connect(ENV.fetch("DATABASE_URL"))
    return yield(db) if block_given?

    db
  ensure
    db&.close if block_given?
  end

  def render_error(status, title, message)
    content = render_template("error", message: message)
    html(status, page(title, content))
  end

  def page(title, content)
    render_template("layout", title: title, content: content)
  end

  def render_template(name, **locals)
    template_binding = binding
    locals.each { |key, value| template_binding.local_variable_set(key, value) }
    ERB.new(File.read(File.join(TEMPLATE_ROOT, "#{name}.erb"))).result(template_binding)
  end

  def static_asset(path)
    file, content_type = ASSETS.fetch(path)
    [200, { "content-type" => content_type, "cache-control" => "no-cache" }, [File.binread(file)]]
  end

  def money(cents)
    format("%.2f", cents.to_i / 100.0)
  end

  def h(value) = CGI.escapeHTML(value.to_s)
  def html(status, body) = [status, { "content-type" => "text/html; charset=utf-8" }, [body]]
  def json(status, object) = [status, { "content-type" => "application/json" }, [JSON.generate(object)]]
  def redirect(location) = [303, { "location" => location }, []]
end

if $PROGRAM_NAME == __FILE__
  Rackup::Handler::WEBrick.run(
    DemoStore.new,
    Host: "0.0.0.0",
    Port: Integer(ENV.fetch("PORT", "3000")),
    AccessLog: [],
    Logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO)
  )
end
