# Destination Adapters

Destination adapters turn a destination config entry into a delivery sink.

Built-in adapter:

```yaml
destinations:
  - name: primary_webhook
    type: webhook
    url: https://example.com/webhooks/postgres
    timeout_seconds: 5
```

The `webhook` adapter remains the only Mammoth OSS destination adapter.

Adapter contract:

```ruby
adapter = Mammoth::Destinations::Registry.fetch("webhook")
sink = adapter.build(destination_config, label: "destinations[0]")
sink.deliver(event)
sink.deliver_transaction(envelope)
sink.name
```

Destination adapters own protocol-specific delivery mechanics. Mammoth still
owns retry, route filtering, fanout, delivered-ledger writes, dead letters, and
replay targeting.

Built-in registration:

```ruby
Mammoth::Destinations::Registry.register(
  "webhook",
  Mammoth::Destinations::WebhookAdapter
)
```

Unknown destination adapter names fail with `Mammoth::ConfigurationError`.
