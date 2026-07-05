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

    def test_migrate_applies_new_migration
      migration = File.join(SQLiteStore::MIGRATION_DIR, "coverage_extra.sql")
      File.write(migration, "CREATE TABLE coverage_extra(id INTEGER PRIMARY KEY);")

      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!

        assert_same store, store.migrate!("coverage_extra.sql")
        assert store.table_exists?("coverage_extra")
        assert store.version_exists?("coverage_extra")
      end
    ensure
      FileUtils.rm_f(migration) if migration
    end

    def test_migrate_wraps_sqlite_errors
      migration = File.join(SQLiteStore::MIGRATION_DIR, "coverage_invalid.sql")
      File.write(migration, "CREATE TABLE broken(")

      with_temp_dir do |dir|
        store = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!

        error = assert_raises(StoreError) { store.migrate!("coverage_invalid.sql") }

        assert_match(/failed to apply migration coverage_invalid.sql/, error.message)
      end
    ensure
      FileUtils.rm_f(migration) if migration
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
