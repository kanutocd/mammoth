# frozen_string_literal: true

module Mammoth
  # Top-level Mammoth application runtime.
  #
  # Application wires Mammoth's delivery-side runtime pieces: configuration,
  # SQLite operational memory, replication consumer, delivery worker, checkpoint
  # store, dead letter store, and webhook sink. Upstream PostgreSQL transport
  # composition stays outside this class so the application runtime consumes an
  # injected CDC work source rather than owning upstream CDC source-adapter
  # lifecycle decisions.
  class Application
    attr_reader :config, :sqlite_store, :consumer, :delivery_worker

    # @param config [Mammoth::Configuration] loaded configuration
    # @param source [#each, nil] injectable event source for tests and demos
    # @param sink [#deliver, nil] optional destination sink
    # @param sleeper [#call] retry sleep strategy
    def initialize(config, source: nil, sink: nil, sleeper: Kernel.method(:sleep))
      @config = config
      @sqlite_store = SQLiteStore.connect(config.dig("sqlite", "path")).bootstrap!
      @consumer = ReplicationConsumer.new(source: source)
      @delivery_worker = build_delivery_worker(sink: sink || WebhookSink.from_config(config), sleeper: sleeper)
    end

    # Start the application runtime and deliver consumed events.
    #
    # @return [Integer] number of processed events
    def start
      processed = 0
      consumer.start do |event|
        delivery_worker.deliver(event)
        processed += 1
      end
      processed
    end

    private

    def build_delivery_worker(sink:, sleeper:)
      DeliveryWorker.from_config(
        config,
        sink: sink,
        checkpoint_store: CheckpointStore.new(sqlite_store),
        dead_letter_store: DeadLetterStore.new(sqlite_store),
        sleeper: sleeper
      )
    end
  end
end
