# frozen_string_literal: true

require "fileutils"
require "sqlite3"
require "time"

module Mammoth
  # Owns Mammoth's local SQLite operational database.
  #
  # The SQLite database is Mammoth's operational memory. It stores only boring,
  # inspectable state required for reliability: schema versions, checkpoints,
  # and dead letters.
  class SQLiteStore
    # Default SQLite database path used by local Mammoth runs.
    DEFAULT_DB_PATH = File.expand_path("../../.sqlite3/mammoth.db", __dir__.to_s)
    # Directory containing bundled SQLite schema migration files.
    MIGRATION_DIR = File.expand_path("sql", __dir__.to_s)
    # Initial schema migration file applied to new SQLite stores.
    BOOTSTRAP_FILE = "__bootstrap__.sql"
    # Synthetic schema version recorded after the bootstrap migration succeeds.
    BOOTSTRAP_VERSION = "__bootstrap__"
    # Table that records applied SQLite schema migrations.
    MIGRATIONS_TABLE = "schema_migrations"

    attr_reader :path

    # Open and return a connected store.
    #
    # @param path [String] SQLite database path
    # @return [Mammoth::SQLiteStore]
    def self.connect(path = DEFAULT_DB_PATH)
      new(path).connect
    end

    # @param path [String] SQLite database path
    def initialize(path = DEFAULT_DB_PATH)
      @path = path
      @database = nil
    end

    # Open the SQLite database and configure conservative operational pragmas.
    #
    # @return [Mammoth::SQLiteStore] self
    def connect
      FileUtils.mkdir_p(File.dirname(path))
      @database = SQLite3::Database.new(path)
      @database.results_as_hash = true
      execute_pragma("journal_mode", "WAL")
      execute_pragma("foreign_keys", "ON")
      execute_pragma("busy_timeout", 5000)
      self
    rescue SQLite3::Exception => e
      raise StoreError, "failed to open SQLite database #{path}: #{e.message}"
    end

    # @return [SQLite3::Database] connected database
    def database
      @database || connect.database
    end

    # Apply the initial schema if it has not yet been applied.
    #
    # @return [Mammoth::SQLiteStore] self
    def bootstrap!
      return self if bootstrapped?

      apply_migration!(BOOTSTRAP_FILE, BOOTSTRAP_VERSION)
      self
    end

    # Apply a migration file unless its version already exists.
    #
    # @param sql_file [String] SQL file name under lib/mammoth/sql
    # @return [Mammoth::SQLiteStore] self
    def migrate!(sql_file)
      bootstrap!
      version_name = File.basename(sql_file, ".sql")
      return self if version_exists?(version_name)

      apply_migration!(sql_file, version_name)
      self
    end

    # @return [Boolean] true when the initial schema is already applied
    def bootstrapped?
      table_exists?(MIGRATIONS_TABLE) && version_exists?(BOOTSTRAP_VERSION)
    end

    # @param table_name [String] table name
    # @return [Boolean] true when a table exists
    def table_exists?(table_name)
      !database.execute(
        "SELECT 1 FROM sqlite_schema WHERE type = ? AND name = ? LIMIT 1",
        ["table", table_name]
      ).empty?
    end

    # @param version_name [String] migration version
    # @return [Boolean] true when a migration version exists
    def version_exists?(version_name)
      return false unless table_exists?(MIGRATIONS_TABLE)

      !database.execute(
        "SELECT 1 FROM schema_migrations WHERE version = ? LIMIT 1",
        [version_name]
      ).empty?
    end

    # Return table names in the operational database.
    #
    # @return [Array<String>] table names
    def tables
      database.execute(
        "SELECT name FROM sqlite_schema WHERE type = 'table' ORDER BY name"
      ).map { |row| row.fetch("name") }
    end

    private

    def apply_migration!(sql_file, version_name)
      sql_path = File.expand_path(sql_file, MIGRATION_DIR)
      raise StoreError, "migration file not found: #{sql_path}" unless File.file?(sql_path)

      database.transaction do
        database.execute_batch(File.read(sql_path))
        database.execute(
          "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
          [version_name, Time.now.utc.iso8601]
        )
      end
    rescue SQLite3::Exception => e
      raise StoreError, "failed to apply migration #{sql_file}: #{e.message}"
    end

    def execute_pragma(name, value)
      database.execute("PRAGMA #{name} = #{value}")
    end
  end
end
