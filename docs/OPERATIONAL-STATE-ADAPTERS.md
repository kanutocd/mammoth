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
adapter.summary
```

Adapter authors must preserve Mammoth's data-plane semantics. A state adapter
stores checkpoints, dead letters, and delivered-envelope ledgers; it must not
invent checkpoint positions or bypass replay rules.

`Application` injects all three stores into its delivery components.
`DeliveryWorker` never derives one store from another or assumes that a store
exposes adapter-specific persistence internals.

Built-in registration:

```ruby
Mammoth::OperationalState::Registry.register(
  "sqlite",
  Mammoth::OperationalState::SQLiteAdapter
)
```

Unknown adapters fail configuration/startup with a clear error.
