# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Sources
    class PostgresSlotHealthTest < Minitest::Test
      def test_reports_each_unready_reason
        cases = [
          [{ wal_status: "lost" }, "wal_status=lost"],
          [{ invalidation_reason: "wal_removed" }, "slot is invalidated: wal_removed"],
          [{ conflicting: true }, "slot is conflicting"],
          [{ restart_lsn: nil }, "slot has no restart LSN"]
        ]

        cases.each do |overrides, reason|
          health = build_health(**overrides)

          refute_predicate health, :ready?
          assert_equal reason, health.reason
        end
      end

      private

      def build_health(**overrides)
        PostgresSlotHealth.new(
          slot_name: "mammoth_prod", present: true, active: true,
          retained_wal_bytes: 8192, wal_status: "reserved", safe_wal_size: 4096,
          inactive_since: nil, invalidation_reason: nil,
          restart_lsn: "0/10", restart_lsn_bytes: 16,
          confirmed_flush_lsn: "0/20", confirmed_flush_lsn_bytes: 32,
          conflicting: false, **overrides
        )
      end
    end
  end
end
