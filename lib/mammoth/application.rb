# frozen_string_literal: true

module Mammoth
  # Top-level Mammoth application composition root.
  #
  # Application wires Mammoth's current v0.1.0 runtime pieces: configuration,
  # SQLite operational memory, replication boundary, delivery worker, checkpoint
  # store, dead letter store, and webhook sink.
  class Application
    attr_reader :config, :sqlite_store, :consumer, :delivery_worker

    # @param config [Mammoth::Configuration] loaded configuration
    # @param source [#each, nil] injectable event source for tests and demos
    # @param adapter [#call, nil] optional source adapter
    # @param sink [#deliver, nil] optional destination sink
    # @param sleeper [#call] retry sleep strategy
    def initialize(config, source: nil, adapter: nil, sink: nil, sleeper: Kernel.method(:sleep))
      @config = config
      @sqlite_store = SQLiteStore.connect(config.dig("sqlite", "path")).bootstrap!
      @consumer = ReplicationConsumer.new(config, source: source, adapter: adapter)
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
