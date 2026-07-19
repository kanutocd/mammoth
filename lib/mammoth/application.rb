# frozen_string_literal: true

module Mammoth
  # Top-level Mammoth application runtime.
  #
  # Application wires Mammoth's delivery-side runtime pieces: configuration,
  # operational-state adapter, replication consumer, delivery worker, checkpoint
  # store, dead-letter store, and webhook sink. Upstream PostgreSQL transport
  # composition stays outside this class so the application runtime consumes an
  # injected CDC work source rather than owning upstream CDC source-adapter
  # lifecycle decisions.
  # rubocop:disable Metrics/ClassLength
  class Application
    attr_reader :config, :state_adapter, :consumer, :delivery_worker, :checkpoint_store, :lifecycle_hooks, :observer,
                :progress_coordinator

    # @param config [Mammoth::Configuration] loaded configuration
    # @param source [#each, nil] injectable event source for tests and demos
    # @param sink [#deliver, nil] optional destination sink
    # @param state_adapter [Mammoth::OperationalState::Adapter, nil] operational state dependency
    # @param sleeper [#call] retry sleep strategy
    # @param lifecycle_hooks [Mammoth::LifecycleHooks, Hash] local lifecycle callbacks
    # @param observer [CDC::Core::Observer, nil] dispatch lifecycle observer
    def initialize(config, source: nil, sink: nil, state_adapter: nil, sleeper: Kernel.method(:sleep),
                   lifecycle_hooks: LifecycleHooks.new, observer: nil)
      @config = config
      @lifecycle_hooks = build_lifecycle_hooks(lifecycle_hooks)
      @observer = observer || MetricsObserver.new
      @state_adapter = state_adapter || build_state_adapter
      @checkpoint_store = @state_adapter.checkpoint_store
      @consumer = ReplicationConsumer.new(source: source || build_source, delivery_unit: delivery_unit)
      @progress_coordinator = build_progress_coordinator
      @delivery_worker = if sink
                           build_delivery_worker(
                             sink: sink,
                             sleeper: sleeper,
                             delivery_policy: destination_delivery_policy(config.data["webhook"] || {})
                           )
                         else
                           build_configured_delivery_worker(sleeper: sleeper)
                         end
    end

    # @return [Mammoth::SQLiteStore] underlying SQLite store for compatibility
    def sqlite_store
      state_adapter.respond_to?(:sqlite_store) ? state_adapter.sqlite_store : nil
    end

    # Start the application runtime and deliver consumed CDC work.
    #
    # @return [Integer] number of processed work units
    def start
      runtime = build_runtime
      processed = nil

      lifecycle_hooks.call(:before_start, application_context(runtime: runtime))
      processed = process_consumer(runtime)
      lifecycle_hooks.call(:after_start, application_context(runtime: runtime, processed: processed))
      processed
    ensure
      lifecycle_hooks.call(:before_shutdown, application_context(runtime: runtime, processed: processed))
      runtime.shutdown if runtime.respond_to?(:shutdown)
      lifecycle_hooks.call(:after_shutdown, application_context(runtime: runtime, processed: processed))
    end

    private

    def build_lifecycle_hooks(hooks)
      return hooks if hooks.is_a?(LifecycleHooks)

      LifecycleHooks.new(hooks)
    end

    def application_context(extra = {})
      {
        config: config,
        state_adapter: state_adapter,
        checkpoint_store: checkpoint_store,
        delivery_worker: delivery_worker
      }.merge(extra)
    end

    def process_consumer(runtime)
      processed = 0

      consumer.start_with_boundaries do |work, group_end|
        progress_coordinator.register(work, group_end:)
        process_work(runtime, work)
        processed += 1
      end

      runtime.flush
      progress_coordinator.finalize
      processed
    end

    def process_work(runtime, work)
      runtime.process(work)
    end

    def build_runtime
      Runtimes::Registry.build(
        runtime_adapter,
        processor: DeliveryProcessor.new(
          delivery_worker:,
          delivery_unit: delivery_unit,
          progress_coordinator: progress_coordinator
        ),
        concurrency: runtime_concurrency,
        timeout: runtime_timeout,
        preserve_order: runtime_preserve_order?,
        batch_size: runtime_batch_size,
        observer: observer
      )
    end

    def build_source
      Sources::Postgres.new(config, checkpoint_store: checkpoint_store)
    end

    def build_progress_coordinator
      DeliveryProgressCoordinator.new(
        checkpoint_store: checkpoint_store,
        source_name: config.dig("mammoth", "name"),
        slot_name: config.dig("replication", "slot"),
        publication_name: Array(config.dig("replication", "publications")).join(","),
        acknowledger: source_acknowledger,
        position_resolver: source_position_resolver
      )
    end

    def source_acknowledger
      source = consumer.source
      source.method(:acknowledge) if source.respond_to?(:acknowledge)
    end

    def source_position_resolver
      source = consumer.source
      source.method(:progress_position_for) if source.respond_to?(:progress_position_for)
    end

    def build_delivery_worker(sink:, sleeper:, delivery_policy: {})
      DeliveryWorker.from_config(
        config,
        sink: sink,
        checkpoint_store: checkpoint_store,
        dead_letter_store: state_adapter.dead_letter_store,
        delivered_envelope_store: state_adapter.delivered_envelope_store,
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
        webhook = config.data.fetch("webhook")
        return [{ sink: WebhookSink.from_config(config), delivery_policy: destination_delivery_policy(webhook) }]
      end

      destinations.map.with_index(1) do |destination, index|
        {
          sink: Destinations::Registry.build(destination, label: "destinations[#{index - 1}]"),
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
        "route_filter" => RouteFilter.new(destination["route"]),
        "payload_policy" => PayloadPolicy.new(destination["payload_policy"])
      }
    end

    def build_state_adapter
      OperationalState::Registry.build_configured(config)
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
  # rubocop:enable Metrics/ClassLength
end
