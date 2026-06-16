# frozen_string_literal: true

module Mammoth
  # Builds and prints a boring operational status snapshot.
  class Status
    attr_reader :config, :sqlite_store

    # Print status for a configuration and optional SQLite store.
    #
    # @param config [Mammoth::Configuration] loaded configuration
    # @param sqlite_store [Mammoth::SQLiteStore, nil] operational store
    # @return [void]
    def self.call(config, sqlite_store: nil)
      new(config, sqlite_store: sqlite_store).call
    end

    # @param config [Mammoth::Configuration] loaded configuration
    # @param sqlite_store [Mammoth::SQLiteStore, nil] operational store
    def initialize(config, sqlite_store: nil)
      @config = config
      @sqlite_store = sqlite_store
    end

    # Print the status snapshot.
    #
    # @return [void]
    def call
      puts "Mammoth: #{config.dig("mammoth", "name")}"
      puts "Replication slot: #{config.dig("replication", "slot")}"
      puts "Replication publications: #{Array(config.dig("replication", "publications")).join(", ")}"
      puts "Runtime: not started"
      puts "SQLite: #{sqlite_path}"
      puts "Webhook: #{config.dig("webhook", "name")}"
      print_store_state if sqlite_store
    end

    private

    def sqlite_path
      config.dig("sqlite", "path")
    end

    def print_store_state
      store = sqlite_store.bootstrap!
      puts "Tables: #{store.tables.join(", ")}"
      puts "Checkpoints: #{CheckpointStore.new(store).count}"
      puts "Dead Letters: #{DeadLetterStore.new(store).count}"
    end
  end
end
