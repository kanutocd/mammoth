# frozen_string_literal: true

module Mammoth
  module OperationalState
    # SQLite-backed operational state adapter used by Mammoth OSS.
    class SQLiteAdapter < Adapter
      attr_reader :sqlite_store

      # @param sqlite_store [Mammoth::SQLiteStore] bootstrapped SQLite store
      def initialize(sqlite_store)
        super()
        @sqlite_store = sqlite_store.bootstrap!
      end

      # Build a SQLite state adapter from Mammoth configuration.
      #
      # @param config [Mammoth::Configuration] loaded configuration
      # @return [Mammoth::OperationalState::SQLiteAdapter]
      def self.from_config(config)
        new(SQLiteStore.connect(config.dig("sqlite", "path")))
      end

      # @return [Mammoth::CheckpointStore]
      def checkpoint_store
        @checkpoint_store ||= CheckpointStore.new(sqlite_store)
      end

      # @return [Mammoth::DeadLetterStore]
      def dead_letter_store
        @dead_letter_store ||= DeadLetterStore.new(sqlite_store)
      end

      # @return [Mammoth::DeliveredEnvelopeStore]
      def delivered_envelope_store
        @delivered_envelope_store ||= DeliveredEnvelopeStore.new(sqlite_store)
      end

      # @return [Hash] JSON-friendly SQLite state summary
      def summary
        super.merge(adapter: "sqlite", path: sqlite_store.path, tables: sqlite_store.tables)
      end
    end
  end
end
