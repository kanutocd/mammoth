<!--
# @title Extensions
-->

# Extensions

Mammoth 1.x exposes explicit extension contracts for adapters.
The contracts are intentionally small and local. Extensions register adapters;
they do not take over Mammoth's delivery semantics.

Mammoth owns:

- PostgreSQL CDC relay behavior
- contiguous checkpoint and upstream acknowledgement semantics
- retry and backoff behavior
- delivered-envelope ledger semantics
- dead-letter persistence and replay rules
- route filtering and fanout behavior
- deterministic destination payload-policy execution

Extensions may provide:

- operational state adapters
- destination adapters
- delivery runtime adapters
- local lifecycle hook callbacks
- configuration providers
- local command orchestration around existing command objects

Destination adapters that advertise prepared-payload support receive the exact
JSON already projected by Mammoth. They must not restore fields, reserialize a
source work item, or apply a second policy. Central policy authoring and fleet
governance may live in Mammoth Platform; deterministic policy execution remains
inside the OSS data plane.

Registration is explicit:

```ruby
Mammoth::Destinations::Registry.register("webhook", Mammoth::Destinations::WebhookAdapter)
Mammoth::Runtimes::Registry.register("inline", Mammoth::Runtimes::InlineAdapter)
Mammoth::OperationalState::Registry.register("sqlite", Mammoth::OperationalState::SQLiteAdapter)
```

Unknown adapter names raise `Mammoth::ConfigurationError`.

Lifecycle hooks are local callbacks around operator-visible actions:

```ruby
hooks = Mammoth::LifecycleHooks.new(
  before_start: ->(context) { audit(context) },
  after_replay: ->(context) { report(context) }
)

Mammoth::Application.new(config, lifecycle_hooks: hooks).start
```

Supported hook events are:

- `before_start`
- `after_start`
- `before_shutdown`
- `after_shutdown`
- `before_replay`
- `after_replay`

Configuration providers let callers load config from files or already parsed
hashes while keeping the same schema validation:

```ruby
file_config = Mammoth::Configuration::Providers::FileProvider.new("config/mammoth.yml").load
hash_config = Mammoth::Configuration.from_hash(data, path: "control-plane")
```

Local command objects sit behind the CLI and are safe integration points for
future agents:

```ruby
state_adapter = Mammoth::OperationalState::Registry.build_configured(config)

Mammoth::Commands::ValidateCommand.new(provider).call
Mammoth::Commands::BootstrapCommand.new(config, state_adapter: state_adapter).call
Mammoth::Commands::StatusCommand.new(config, state_adapter: state_adapter).call
Mammoth::Commands::StartCommand.new(config, lifecycle_hooks: hooks).call
Mammoth::Commands::DeadLettersCommand.new(
  argv,
  state_adapter: state_adapter,
  lifecycle_hooks: hooks
).call
```

These APIs are useful in OSS and are also integration seams for the paid
Mammoth Platform. They keep the local data plane inspectable and testable
without introducing a control plane into Mammoth OSS.

See also:

- [Operational State Adapters](./OPERATIONAL-STATE-ADAPTERS.md)
- [Destination Adapters](./DESTINATION-ADAPTERS.md)
- [Runtime Adapters](./RUNTIME-ADAPTERS.md)
