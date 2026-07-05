# frozen_string_literal: true

require "test_helper"

module Mammoth
  class RegistryTest < Minitest::Test
    def test_registers_and_fetches_adapter
      registry = Registry.new("example")
      adapter = Object.new

      registry.register(:adapter, adapter)

      assert_same adapter, registry.fetch("adapter")
      assert_equal ["adapter"], registry.names
    end

    def test_rejects_duplicate_registration
      registry = Registry.new("example")
      registry.register("adapter", Object.new)

      error = assert_raises(ConfigurationError) { registry.register("adapter", Object.new) }

      assert_match(/already registered/, error.message)
    end

    def test_rejects_unknown_adapter
      error = assert_raises(ConfigurationError) { Registry.new("example").fetch("missing") }

      assert_match(/unknown example adapter: missing/, error.message)
    end
  end
end
