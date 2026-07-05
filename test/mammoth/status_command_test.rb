# frozen_string_literal: true

require "test_helper"

module Mammoth
  class StatusCommandTest < Minitest::Test
    def test_status_command_prints_status_to_injected_output
      output = StringIO.new
      config = Configuration.load(fixture_config_path)

      result = Commands::StatusCommand.new(config, output: output).call

      assert_equal 0, result
      assert_match(/Mammoth: local_mammoth/, output.string)
      assert_match(/Operational state: sqlite/, output.string)
      assert_match(/Features: .*fanout/, output.string)
    end
  end
end
