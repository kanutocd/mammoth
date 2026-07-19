<!--
# @title Operational State Adapters
-->

# Operational State Adapters

Operational state adapters expose Mammoth's local reliability stores through a
stable contract.

Built-in adapter:

```yaml
operational_state:
  adapter: sqlite
```

The `sqlite` adapter remains the Mammoth OSS default.

Adapter contract:

```ruby
adapter.checkpoint_store
adapter.dead_letter_store
adapter.delivered_envelope_store
adapter.bootstrap!
adapter.ready?
adapter.summary
```

Adapter authors must preserve Mammoth's data-plane semantics. A state adapter
stores checkpoints, dead letters, and delivered-envelope ledgers; it must not
invent checkpoint positions or bypass replay rules.

`Application` injects all three stores into its delivery components. The shared
progress coordinator is the sole checkpoint writer and persists only contiguous
durable progress before upstream acknowledgement.
`DeliveryWorker` never derives one store from another or assumes that a store
exposes adapter-specific persistence internals.

Observability, status, bootstrap, and dead-letter commands receive this adapter
contract as well. Backend-specific readiness errors, paths, and schema details
belong in the adapter implementation and its JSON-friendly `summary`.

Built-in registration:

```ruby
Mammoth::OperationalState::Registry.register(
  "sqlite",
  Mammoth::OperationalState::SQLiteAdapter
)
```

Unknown adapters fail configuration/startup with a clear error.
