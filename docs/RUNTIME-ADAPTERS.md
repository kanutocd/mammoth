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

The processor passed to a runtime is `Mammoth::DeliveryProcessor`. It implements
`CDC::Core::Processor` and returns a `CDC::Core::ProcessorResult` for every work
item. `DeliveryWorker` still owns retry, checkpoint, delivered-ledger, and DLQ
behavior; the processor only translates its final delivery summary into the
core result contract.

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
