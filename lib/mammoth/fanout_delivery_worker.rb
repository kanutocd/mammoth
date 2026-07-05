# frozen_string_literal: true

module Mammoth
  # Delivers one CDC work item to multiple destination-specific workers.
  class FanoutDeliveryWorker
    attr_reader :delivery_workers

    # @param delivery_workers [Array<Mammoth::DeliveryWorker>] destination workers
    def initialize(delivery_workers)
      raise ConfigurationError, "at least one destination is required" if delivery_workers.empty?

      @delivery_workers = delivery_workers
    end

    # Deliver an event to every configured destination.
    #
    # @param event [Hash, #to_h] normalized event
    # @return [Hash] aggregate fanout summary
    def deliver(event)
      fanout(:deliver, event)
    end

    # Deliver a transaction envelope to every configured destination.
    #
    # @param envelope [#events, #transaction_id] CDC transaction envelope
    # @return [Hash] aggregate fanout summary
    def deliver_transaction(envelope)
      fanout(:deliver_transaction, envelope)
    end

    # Deliver an event to one configured destination.
    #
    # @param destination_name [String] destination name
    # @param event [Hash, #to_h] normalized event
    # @return [Hash] destination delivery summary
    def deliver_to(destination_name, event)
      worker_for(destination_name).deliver(event)
    end

    # Deliver a transaction envelope to one configured destination.
    #
    # @param destination_name [String] destination name
    # @param envelope [#events, #transaction_id] CDC transaction envelope
    # @return [Hash] destination delivery summary
    def deliver_transaction_to(destination_name, envelope)
      worker_for(destination_name).deliver_transaction(envelope)
    end

    private

    def fanout(delivery_method, work)
      results = delivery_workers.map { |worker| worker.public_send(delivery_method, work) }
      {
        status: aggregate_status(results),
        destinations: results,
        delivered: results.count { |result| result.fetch(:status) == "delivered" },
        skipped: results.count { |result| result.fetch(:status) == "skipped" },
        dead_lettered: results.count { |result| result.fetch(:status) == "dead_lettered" }
      }
    end

    def aggregate_status(results)
      return "fanout_delivered" if results.all? { |result| %w[delivered skipped].include?(result.fetch(:status)) }

      "fanout_partial"
    end

    def worker_for(destination_name)
      delivery_workers.find { |worker| worker.send(:destination_name) == destination_name } ||
        raise(ConfigurationError, "destination not configured: #{destination_name}")
    end
  end
end
