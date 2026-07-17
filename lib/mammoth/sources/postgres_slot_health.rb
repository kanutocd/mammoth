# frozen_string_literal: true

module Mammoth
  module Sources
    # Immutable operator-facing health snapshot for one PostgreSQL replication slot.
    #
    # This is a Mammoth-owned policy view. The transport layer supplies catalog
    # facts; Mammoth decides whether they make the configured source ready for
    # continuous delivery.
    # Typed PostgreSQL slot health and readiness policy.
    class PostgresSlotHealth
      attr_reader :slot_name, :present, :active, :retained_wal_bytes, :wal_status, :safe_wal_size, :inactive_since,
                  :invalidation_reason, :restart_lsn, :restart_lsn_bytes, :confirmed_flush_lsn,
                  :confirmed_flush_lsn_bytes, :conflicting

      # Build a PostgreSQL slot health snapshot from normalized catalog facts.
      #
      # @return [void]
      def initialize(slot_name:, present:, active:, retained_wal_bytes:, wal_status:, safe_wal_size:, inactive_since:,
                     invalidation_reason:, restart_lsn:, restart_lsn_bytes:, confirmed_flush_lsn:,
                     confirmed_flush_lsn_bytes:, conflicting:)
        @slot_name = slot_name
        @present = present
        @active = active
        @retained_wal_bytes = retained_wal_bytes
        @wal_status = wal_status
        @safe_wal_size = safe_wal_size
        @inactive_since = inactive_since
        @invalidation_reason = invalidation_reason
        @restart_lsn = restart_lsn
        @restart_lsn_bytes = restart_lsn_bytes
        @confirmed_flush_lsn = confirmed_flush_lsn
        @confirmed_flush_lsn_bytes = confirmed_flush_lsn_bytes
        @conflicting = conflicting
        freeze
      end

      # Build a snapshot for a missing configured slot.
      #
      # @param slot_name [String] configured replication slot
      # @return [PostgresSlotHealth]
      def self.missing(slot_name)
        new(
          slot_name:, present: false, active: false, retained_wal_bytes: nil,
          wal_status: nil, safe_wal_size: nil, inactive_since: nil,
          invalidation_reason: nil, restart_lsn: nil, restart_lsn_bytes: nil,
          confirmed_flush_lsn: nil, confirmed_flush_lsn_bytes: nil, conflicting: false
        )
      end

      # Whether the slot is present, active, and retaining usable WAL.
      #
      # @return [Boolean]
      def ready?
        reason.nil?
      end

      # Operator-facing reason the slot is not ready.
      #
      # @return [String, nil]
      def reason
        return "slot is missing" unless present
        return "slot is inactive" unless active
        return "wal_status=#{wal_status}" if %w[lost unreserved].include?(wal_status)
        return "slot is invalidated: #{invalidation_reason}" unless blank?(invalidation_reason)
        return "slot is conflicting" if conflicting
        return "slot has no restart LSN" if blank?(restart_lsn)

        nil
      end

      # Stable readiness payload without transport-library types.
      #
      # @return [Hash]
      def summary
        {
          slot_name:, present:, active:, retained_wal_bytes:, wal_status:, safe_wal_size:, inactive_since:,
          invalidation_reason:, restart_lsn:, restart_lsn_bytes:, confirmed_flush_lsn:,
          confirmed_flush_lsn_bytes:, conflicting:, ready: ready?, reason:
        }
      end

      private

      def blank?(value)
        value.nil? || value == ""
      end
    end
  end
end
