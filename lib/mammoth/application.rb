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
    attr_reader :config, :sqlite_store, :consumer, :delivery_worker, :checkpoint_store

    # @param config [Mammoth::Configuration] loaded configuration
    # @param source [#each, nil] injectable event source for tests and demos
    # @param sink [#deliver, nil] optional destination sink
    # @param sleeper [#call] retry sleep strategy
    def initialize(config, source: nil, sink: nil, sleeper: Kernel.method(:sleep))
      @config = config
      @sqlite_store = SQLiteStore.connect(config.dig("sqlite", "path")).bootstrap!
      @checkpoint_store = CheckpointStore.new(sqlite_store)
      @consumer = ReplicationConsumer.new(source: source || build_source, delivery_unit: delivery_unit)
      @delivery_worker = sink ? build_delivery_worker(sink: sink, sleeper: sleeper) : build_configured_delivery_worker(sleeper:)
    end

    # Start the application runtime and deliver consumed CDC work.
    #
    # @return [Integer] number of processed work units
    def start
      runtime = build_runtime
      processed = 0
      batch = [nil].compact

      consumer.start do |work|
        if runtime_batching?(runtime)
          batch << work
          next unless batch.size >= runtime_batch_size

          processed += process_batch(runtime, batch)
          batch = []
        else
          process_work(runtime, work)
          processed += 1
        end
      end

      processed += process_batch(runtime, batch) if runtime_batching?(runtime) && batch.any?
      processed
    ensure
      runtime.shutdown if runtime.respond_to?(:shutdown)
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

    def process_batch(runtime, batch)
      runtime.process_many(batch)
      batch.size
    end

    def runtime_batching?(runtime)
      runtime && runtime_batch_size > 1
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

    def build_source
      Sources::Postgres.new(config, checkpoint_store: checkpoint_store)
    end

    def build_delivery_worker(sink:, sleeper:, delivery_policy: {})
      DeliveryWorker.from_config(
        config,
        sink: sink,
        checkpoint_store: checkpoint_store,
        dead_letter_store: DeadLetterStore.new(sqlite_store),
        sleeper: sleeper,
        delivery_policy: delivery_policy
      )
    end

    def build_configured_delivery_worker(sleeper:)
      workers = destination_specs.map do |spec|
        build_delivery_worker(sink: spec.fetch(:sink), sleeper:, delivery_policy: spec.fetch(:delivery_policy))
      end
      return workers.fetch(0) if workers.one?

      FanoutDeliveryWorker.new(workers)
    end

    def destination_specs
      destinations = config.data["destinations"]
      unless destinations
        delivery_policy = {} # : Hash[String, untyped]
        return [{ sink: WebhookSink.from_config(config), delivery_policy: delivery_policy }]
      end

      destinations.map.with_index(1) do |destination, index|
        {
          sink: WebhookSink.from_destination_config(destination, label: "destinations[#{index - 1}]"),
          delivery_policy: destination_delivery_policy(destination)
        }
      end
    end

    def destination_delivery_policy(destination)
      retry_config = destination["retry"] || {}
      {
        "enabled" => destination.fetch("enabled", true),
        "max_attempts" => retry_config.fetch("max_attempts", config.dig("retry", "max_attempts")),
        "schedule_seconds" => retry_config.fetch("schedule_seconds", config.dig("retry", "schedule_seconds")),
        "route_filter" => RouteFilter.new(destination["route"])
      }
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

    def runtime_batch_size
      config.dig("runtime", "batch_size") || 1
    end

    def runtime_preserve_order?
      value = config.dig("runtime", "preserve_order")
      value.nil? || value
    end
  end
end
