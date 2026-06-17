# Changelog

## Unreleased


## [0.1.0] - 2026-06-17

Initial public release of Mammoth.

### Added

- PostgreSQL logical replication source integration via pgoutput.
- CDC event normalization through the CDC ecosystem.
- Webhook delivery destination.
- SQLite-backed operational state storage.
- Checkpoint persistence infrastructure.
- Dead-letter persistence infrastructure.
- Retry handling for failed webhook deliveries.
- Configuration validation command.
- Operational state bootstrap command.
- Operational status command.
- Sample event delivery command.
- Helm chart for Kubernetes deployments.
- Persistent volume support for SQLite operational state.
- Example configurations and runnable demonstrations.

### Examples

- `examples/postgres_webhook`

  - Demonstrates webhook delivery using sample CDC-shaped events.

- `examples/live_postgres_webhook`

  - Demonstrates end-to-end PostgreSQL logical replication.
  - Demonstrates replication slot management.
  - Demonstrates webhook delivery from live database changes.

- `examples/operational_state`

  - Demonstrates operational state bootstrap.
  - Demonstrates checkpoint and dead-letter schema initialization.

- `examples/failing_webhook_retry`

  - Demonstrates retry exhaustion behavior.
  - Demonstrates durable dead-letter persistence.

- `examples/kubernetes_helm`

  - Demonstrates Helm-based deployment.
  - Demonstrates PVC-backed operational memory.

### Validation

The 0.1.0 release was manually validated through:

- PostgreSQL logical replication slot creation and consumption.
- Idle replication connections exceeding one hour.
- Post-idle event delivery.
- Webhook delivery success path.
- Webhook failure and dead-letter path.
- SQLite checkpoint and dead-letter persistence.
- Helm chart rendering and installation.
- Kubernetes deployment on Kind.
- PVC-backed operational state storage.

### Notes

Mammoth currently operates as a single active consumer per PostgreSQL logical replication slot. The default Helm deployment uses a single replica to align with PostgreSQL logical replication semantics.
