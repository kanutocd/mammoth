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

The processor passed to a runtime is still `Mammoth::DeliveryProcessor`.
`DeliveryWorker` still owns retry, checkpoint, delivered-ledger, and DLQ
behavior.

Built-in registration:

```ruby
Mammoth::Runtimes::Registry.register("inline", Mammoth::Runtimes::InlineAdapter)
Mammoth::Runtimes::Registry.register("concurrent", Mammoth::Runtimes::ConcurrentAdapter)
```

Unknown runtime adapter names fail with `Mammoth::ConfigurationError`.
