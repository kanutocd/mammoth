<!--
# @title Runtime Adapters
-->

# Runtime Adapters

Runtime adapters execute downstream delivery work. They do not own correctness.

Built-in adapters:

```yaml
runtime:
  adapter: inline
```

```yaml
runtime:
  adapter: concurrent
  concurrency: 5
  preserve_order: true
```

Adapter contract:

```ruby
runtime.process_many(work_items)
runtime.shutdown
```

The runtime registry wraps the selected adapter runtime in
`Mammoth::Runtimes::BatchingRuntime`. That execution boundary accepts individual
core work through `process`, owns `runtime.batch_size` accumulation, and submits
full or final partial batches through the adapter's `process_many` method.
`Mammoth::Application` coordinates `flush` and `shutdown` lifecycle calls but
does not buffer or partition work itself.

The processor passed to a runtime is `Mammoth::DeliveryProcessor`. It implements
`CDC::Core::Processor` and returns a `CDC::Core::ProcessorResult` for every work
item. `DeliveryWorker` owns retry, delivered-ledger, and DLQ behavior. After a
durable result, the processor reports completion to the shared contiguous
progress coordinator; the coordinator alone advances checkpoints and upstream
acknowledgements. A source-owned resolver supplies the durable position, keeping
PostgreSQL transport LSNs out of generic runtime and CDC-core contracts.

Runtime inputs are exact `CDC::Core::ChangeEvent` or
`CDC::Core::TransactionEnvelope` instances. Runtime adapters should not accept
hashes or private objects that merely expose similar methods.

Both built-in runtimes accept a `CDC::Core::Observer` and emit canonical
`dispatch_started`, `dispatch_succeeded`, `dispatch_failed`, and
`dispatch_skipped` notifications. `Mammoth::Application` installs
`Mammoth::MetricsObserver` by default. Custom runtime adapters should preserve
the same processor-result and observer lifecycle contract.

Built-in registration:

```ruby
Mammoth::Runtimes::Registry.register("inline", Mammoth::Runtimes::InlineAdapter)
Mammoth::Runtimes::Registry.register("concurrent", Mammoth::Runtimes::ConcurrentAdapter)
```

Unknown runtime adapter names fail with `Mammoth::ConfigurationError`.
