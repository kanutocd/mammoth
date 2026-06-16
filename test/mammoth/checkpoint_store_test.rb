# frozen_string_literal: true

require "test_helper"

module Mammoth
  class CheckpointStoreTest < Minitest::Test
    def test_writes_and_fetches_checkpoint
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = CheckpointStore.new(sqlite)

        row = store.write(
          source_name: "postgresql",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          last_lsn: "0/16F4A8B0"
        )

        assert_equal "postgresql", row.fetch("source_name")
        assert_equal "0/16F4A8B0", row.fetch("last_lsn")
        assert_equal 1, store.count
      end
    end

    def test_updates_existing_checkpoint
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = CheckpointStore.new(sqlite)

        store.write(
          source_name: "postgresql",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          last_lsn: "0/1"
        )
        row = store.write(
          source_name: "postgresql",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          last_lsn: "0/2"
        )

        assert_equal "0/2", row.fetch("last_lsn")
        assert_equal 1, store.count
      end
    end

    def test_fetch_returns_nil_for_missing_checkpoint
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = CheckpointStore.new(sqlite)

        assert_nil store.fetch(source_name: "postgresql", slot_name: "missing")
      end
    end
  end
end
