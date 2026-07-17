# frozen_string_literal: true

require "json"
require "test_helper"

module Mammoth
  class CommandsTest < Minitest::Test
    def test_validate_command_uses_provider
      output = StringIO.new
      provider = Configuration::Providers::FileProvider.new(fixture_config_path)

      assert_equal 0, Commands::ValidateCommand.new(provider, output: output).call
      assert_match(/Configuration OK:/, output.string)
    end

    def test_bootstrap_command_initializes_sqlite
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config = Configuration.from_hash(YAML.safe_load(disabled_destination_config(db_path), aliases: false))
        output = StringIO.new

        assert_equal 0, Commands::BootstrapCommand.new(config, output: output).call

        assert File.file?(db_path)
        assert_match(/Operational state initialized/, output.string)
        assert_match(/Adapter: sqlite/, output.string)
      end
    end

    def test_bootstrap_command_uses_generic_state_adapter_summary
      adapter = BootstrapAdapter.new
      output = StringIO.new

      assert_equal 0, Commands::BootstrapCommand.new(
        Configuration.load(fixture_config_path),
        state_adapter: adapter,
        output: output
      ).call

      assert adapter.bootstrapped
      assert_match(/Adapter: memory/, output.string)
      refute_match(/Path:|Tables:/, output.string)
    end

    def test_start_command_uses_lifecycle_hooks
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config = Configuration.from_hash(YAML.safe_load(disabled_destination_config(db_path), aliases: false))
        output = StringIO.new
        seen = []
        hooks = { after_start: ->(context) { seen << context.fetch(:processed) } }

        command = Commands::StartCommand.new(
          config,
          source: [PersistedPayloadDeserializer.event(sample_event)],
          output: output,
          lifecycle_hooks: hooks
        )

        assert_equal 0, command.call

        assert_equal [1], seen
        assert_match(/Processed events: 1/, output.string)
      end
    end

    def test_deliver_sample_command_delivers_json_event
      with_temp_dir do |dir|
        db_path = File.join(dir, "mammoth.db")
        config = Configuration.from_hash(YAML.safe_load(disabled_destination_config(db_path), aliases: false))
        event_path = write_file(File.join(dir, "event.json"), JSON.generate(sample_event))
        output = StringIO.new

        assert_equal 0, Commands::DeliverSampleCommand.new(config, event_path: event_path, output: output).call

        assert_match(/Processed sample events: 1/, output.string)
      end
    end

    def test_deliver_sample_command_reports_missing_file
      config = Configuration.load(fixture_config_path)
      error = assert_raises(ConfigurationError) do
        Commands::DeliverSampleCommand.new(config, event_path: "missing.json").call
      end

      assert_match(/event JSON file not found/, error.message)
    end

    def test_dead_letters_command_accepts_hash_lifecycle_hooks
      command = DeadLetterCommands.new(["dead-letters"], lifecycle_hooks: {})

      assert_instance_of LifecycleHooks, command.lifecycle_hooks
    end

    class BootstrapAdapter < OperationalState::Adapter
      attr_reader :bootstrapped

      def bootstrap!
        @bootstrapped = true
        self
      end

      def summary = { adapter: "memory" }
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

    def disabled_destination_config(db_path)
      minimal_config(sqlite_path: db_path).sub(/^webhook:.*?(?=^retry:)/m, <<~YAML)
        destinations:
          - name: primary_webhook
            type: webhook
            enabled: false
            url: https://example.com/webhooks/postgres
            timeout_seconds: 5

      YAML
    end
  end
end
