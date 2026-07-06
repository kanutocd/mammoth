# frozen_string_literal: true

module Mammoth
  # Executes optional lifecycle callbacks around local Mammoth operations.
  #
  # Hooks are intentionally in-process and explicit. They give extensions and
  # future control agents stable observation points without changing the data
  # plane or introducing remote behavior into OSS.
  class LifecycleHooks
    EVENTS = %i[
      before_start
      after_start
      before_shutdown
      after_shutdown
      before_replay
      after_replay
    ].freeze
    EMPTY_CALLBACKS = [nil].compact.freeze

    attr_reader :callbacks

    # @param callbacks [Hash] lifecycle callbacks keyed by event name
    def initialize(callbacks = {})
      @callbacks = normalize(callbacks || {})
    end

    # @param event [Symbol, String] lifecycle event
    # @param context [Hash] event context
    # @return [void]
    def call(event, context = {})
      event = event.to_sym
      raise ConfigurationError, "unknown lifecycle hook: #{event}" unless EVENTS.include?(event)

      callback_list = callbacks.fetch(event, EMPTY_CALLBACKS)
      # @type var callback_list: untyped
      Array(callback_list).each do |callback|
        # @type var callback: untyped
        callback.call(context.merge(event: event))
      end
      nil
    end

    private

    def normalize(callbacks)
      normalized = {}
      # @type var normalized: Hash[Symbol, untyped]
      callbacks.each_with_object(normalized) do |(event, callback), memo|
        key = event.to_sym
        raise ConfigurationError, "unknown lifecycle hook: #{key}" unless EVENTS.include?(key)

        memo[key] = Array(callback)
      end
    end
  end
end
