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
      @consumer = ReplicationConsumer.new(source: source, delivery_unit: delivery_unit)
      @delivery_worker = build_delivery_worker(sink: sink || WebhookSink.from_config(config), sleeper: sleeper)
    end

    # Start the application runtime and deliver consumed CDC work.
    #
    # @return [Integer] number of processed work units
    def start
      runtime = build_runtime
      processed = 0

      consumer.start do |work|
        process_work(runtime, work)
        processed += 1
      end

      processed
    ensure
      runtime&.shutdown if runtime.respond_to?(:shutdown)
    end

    private

    def process_work(runtime, work)
      if runtime
        runtime.process_many([work])
      elsif transaction_delivery?
        delivery_worker.deliver_transaction(work)
      else
        delivery_worker.deliver(work)
      end
    end

    def build_runtime
      return unless runtime_adapter == "concurrent"

      ConcurrentDeliveryRuntime.new(
        processor: DeliveryProcessor.new(delivery_worker:, delivery_unit: delivery_unit),
        concurrency: runtime_concurrency,
        timeout: runtime_timeout,
        preserve_order: runtime_preserve_order?
      )
    end

    def build_delivery_worker(sink:, sleeper:)
      DeliveryWorker.from_config(
        config,
        sink: sink,
        checkpoint_store: CheckpointStore.new(sqlite_store),
        dead_letter_store: DeadLetterStore.new(sqlite_store),
        sleeper: sleeper
      )
    end

    def transaction_delivery?
      delivery_unit == :transaction
    end

    def delivery_unit
      (config.dig("delivery", "unit") || "event").to_sym
    end

    def runtime_adapter
      config.dig("runtime", "adapter") || "inline"
    end

    def runtime_concurrency
      config.dig("runtime", "concurrency") || 1
    end

    def runtime_timeout
      config.dig("runtime", "timeout_seconds")
    end

    def runtime_preserve_order?
      value = config.dig("runtime", "preserve_order")
      value.nil? || value
    end
  end
end
