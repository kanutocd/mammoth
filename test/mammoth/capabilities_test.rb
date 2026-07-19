# frozen_string_literal: true

require "test_helper"

module Mammoth
  class CapabilitiesTest < Minitest::Test
    def test_reports_configured_capabilities
      config = Configuration.load(fixture_config_path)

      capabilities = Capabilities.call(config)

      assert_equal "sqlite", capabilities.fetch(:operational_state)
      assert_equal ["webhook"], capabilities.fetch(:destinations)
      assert_includes capabilities.fetch(:runtimes), "inline"
      assert_includes capabilities.fetch(:runtimes), "concurrent"
      assert_includes capabilities.fetch(:features), "routing"
      assert_includes capabilities.fetch(:features), "fanout"
      assert_includes capabilities.fetch(:features), "payload_policies"
    end
  end
end
