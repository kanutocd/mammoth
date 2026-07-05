# frozen_string_literal: true

require "test_helper"

module Mammoth
  class OperationalStateAdapterTest < Minitest::Test
    def test_sqlite_adapter_exposes_working_stores
      with_temp_dir do |dir|
        adapter = OperationalState::SQLiteAdapter.new(SQLiteStore.connect(File.join(dir, "mammoth.db")))

        adapter.checkpoint_store.write(
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          last_lsn: "0/1"
        )
        adapter.dead_letter_store.write(event: sample_event, destination_name: "primary_webhook")

        assert_equal 1, adapter.checkpoint_store.count
        assert_equal 1, adapter.dead_letter_store.count
        assert_equal 0, adapter.delivered_envelope_store.count
        assert_equal "sqlite", adapter.summary.fetch(:adapter)
      end
    end

    def test_registry_builds_sqlite_adapter
      with_temp_dir do |dir|
        config = Configuration.load(
          write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: File.join(dir, "mammoth.db")))
        )

        adapter = OperationalState::Registry.build("sqlite", config)

        assert_instance_of OperationalState::SQLiteAdapter, adapter
      end
    end

    def test_base_adapter_requires_implementation
      adapter = OperationalState::Adapter.new

      assert_match(/checkpoint_store/, assert_raises(NotImplementedError) { adapter.checkpoint_store }.message)
      assert_match(/dead_letter_store/, assert_raises(NotImplementedError) { adapter.dead_letter_store }.message)
      assert_match(/delivered_envelope_store/,
                   assert_raises(NotImplementedError) { adapter.delivered_envelope_store }.message)
    end

    def test_operational_state_registry_names_include_sqlite
      assert_includes OperationalState::Registry.names, "sqlite"
    end

    private

    def sample_event
      {
        "event_id" => "event-1",
        "source" => "postgresql",
        "operation" => "insert",
        "namespace" => "public",
        "entity" => "orders",
        "source_position" => "0/1",
        "data" => { "id" => 1 }
      }
    end
  end
end
