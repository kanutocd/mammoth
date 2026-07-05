# Extensions

Mammoth OSS 0.7.0 introduces explicit extension contracts for future adapters.
The contracts are intentionally small and local. Extensions register adapters;
they do not take over Mammoth's delivery semantics.

Mammoth owns:

- PostgreSQL CDC relay behavior
- checkpoint semantics
- retry and backoff behavior
- delivered-envelope ledger semantics
- dead-letter persistence and replay rules
- route filtering and fanout behavior

Extensions may provide:

- operational state adapters
- destination adapters
- delivery runtime adapters

Registration is explicit:

```ruby
Mammoth::Destinations::Registry.register("webhook", Mammoth::Destinations::WebhookAdapter)
Mammoth::Runtimes::Registry.register("inline", Mammoth::Runtimes::InlineAdapter)
Mammoth::OperationalState::Registry.register("sqlite", Mammoth::OperationalState::SQLiteAdapter)
```

Unknown adapter names raise `Mammoth::ConfigurationError`.

These APIs are the foundation for Mammoth Pro, but they are useful in OSS too:
they make the data-plane seams inspectable and testable without introducing a
control plane.

See also:

- [Operational State Adapters](./OPERATIONAL-STATE-ADAPTERS.md)
- [Destination Adapters](./DESTINATION-ADAPTERS.md)
- [Runtime Adapters](./RUNTIME-ADAPTERS.md)
