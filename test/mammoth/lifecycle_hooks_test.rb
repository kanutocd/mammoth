# frozen_string_literal: true

require "test_helper"

module Mammoth
  class LifecycleHooksTest < Minitest::Test
    def test_calls_registered_callbacks_with_event_context
      seen = []
      hooks = LifecycleHooks.new(before_start: ->(context) { seen << context })

      hooks.call(:before_start, processed: 0)

      assert_equal :before_start, seen.fetch(0).fetch(:event)
      assert_equal 0, seen.fetch(0).fetch(:processed)
    end

    def test_accepts_string_keys_and_multiple_callbacks
      seen = []
      hooks = LifecycleHooks.new("after_start" => [->(_context) { seen << 1 }, ->(_context) { seen << 2 }])

      hooks.call("after_start")

      assert_equal [1, 2], seen
    end

    def test_rejects_unknown_hook_on_initialize
      error = assert_raises(ConfigurationError) { LifecycleHooks.new(nope: ->(_context) {}) }

      assert_match(/unknown lifecycle hook: nope/, error.message)
    end

    def test_rejects_unknown_hook_on_call
      error = assert_raises(ConfigurationError) { LifecycleHooks.new.call(:nope) }

      assert_match(/unknown lifecycle hook: nope/, error.message)
    end
  end
end
