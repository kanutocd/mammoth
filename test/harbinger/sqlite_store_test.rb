# frozen_string_literal: true

require "test_helper"

module Mammoth
  class SQLiteStoreTest < Minitest::Test
    def test_bootstrap_creates_operational_tables
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!

        assert store.bootstrapped?
        assert_includes store.tables, "schema_migrations"
        assert_includes store.tables, "checkpoints"
        assert_includes store.tables, "dead_letters"
      end
    end

    def test_bootstrap_is_idempotent
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db"))

        store.bootstrap!
        store.bootstrap!

        count = store.database.get_first_value("SELECT COUNT(*) FROM schema_migrations")
        assert_equal 1, count
      end
    end

    def test_reports_missing_migration_file
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!

        error = assert_raises(StoreError) { store.migrate!("missing.sql") }

        assert_match(/migration file not found/, error.message)
      end
    end

    def test_version_exists_returns_false_before_bootstrap
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db"))

        refute store.version_exists?("missing")
      end
    end

    def test_migrate_skips_existing_version
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!

        assert_same store, store.migrate!(SQLiteStore::BOOTSTRAP_FILE)
        assert_equal 1, store.database.get_first_value("SELECT COUNT(*) FROM schema_migrations")
      end
    end

    def test_connect_wraps_sqlite_open_errors
      with_temp_dir do |dir|
        error = assert_raises(StoreError) { SQLiteStore.connect(dir) }

        assert_match(/failed to open SQLite database/, error.message)
      end
    end

    def test_table_exists_returns_false_for_missing_table
      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!

        refute store.table_exists?("missing")
      end
    end
  end
end
