# frozen_string_literal: true

# Available Demo Store actions and the intent shown before consequential writes.
module DemoOrderActions
  ALL = {
    "pending" => [
      {
        label: "Pay",
        endpoint: "pay",
        confirmation: "Record payment for this pending order?\n\n" \
                      "This runs one atomic PostgreSQL transaction that marks the order as paid " \
                      "and inserts a captured payment. Mammoth will emit one transaction webhook " \
                      "containing both events."
      },
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
      {
        label: "Cancel",
        endpoint: "cancel",
        confirmation: "Cancel this paid order?\n\n" \
                      "The order will remain in PostgreSQL with status cancelled. " \
                      "The captured payment will not be edited or deleted; instead, one atomic " \
                      "transaction will add an equal negative payment reversal. Mammoth will " \
                      "emit one transaction webhook containing the order update and reversal."
      }
    ],
    "cancelled" => [],
    "shipped" => [
      { label: "Receive", endpoint: "status", status: "received" }
    ],
    "received" => []
  }.freeze
end
