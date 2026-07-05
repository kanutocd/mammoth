# frozen_string_literal: true

require "test_helper"

module Mammoth
  class RouteFilterTest < Minitest::Test
    def test_matches_event_by_schema_table_and_operation
      route = RouteFilter.new("schemas" => ["public"], "tables" => ["orders"], "operations" => ["insert"])

      assert route.match?(sample_event("insert", "public", "orders"), serializer: EventSerializer)
      refute route.match?(sample_event("delete", "public", "orders"), serializer: EventSerializer)
      refute route.match?(sample_event("insert", "private", "orders"), serializer: EventSerializer)
      refute route.match?(sample_event("insert", "public", "users"), serializer: EventSerializer)
    end

    def test_matches_transaction_when_any_event_matches
      route = RouteFilter.new("tables" => ["orders"])
      envelope = Data.define(:events, :transaction_id).new(
        [
          sample_event("insert", "public", "users"),
          sample_event("update", "public", "orders")
        ],
        "tx-1"
      )

      assert route.match?(envelope, serializer: TransactionEnvelopeSerializer)
    end

    def test_empty_route_matches_everything
      assert RouteFilter.new.match?(sample_event("delete", "audit", "log_entries"), serializer: EventSerializer)
    end

    private

    def sample_event(operation, namespace, entity)
      {
        "event_id" => "#{namespace}-#{entity}-#{operation}",
        "operation" => operation,
        "namespace" => namespace,
        "entity" => entity,
        "source_position" => "0/1"
      }
    end
  end
end
