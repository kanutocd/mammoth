# Changelog

## Unreleased

## [0.1.1] - 2026-06-17

Documentation and operational guidance release.

### Added

* Documentation site structure under `docs/`.
* Quick Start guide.
* PostgreSQL setup guide.
* Configuration reference.
* CLI reference.
* Operational state guide.
* Examples guide.
* Helm deployment guide.
* Troubleshooting guide.

### Improved

* GitHub Pages documentation experience.
* API documentation discoverability.
* Documentation navigation and onboarding flow.
* Cross-linking between guides and API reference.

### Clarified

* PostgreSQL logical replication requirements.
* Publication and replication slot expectations.
* SQLite operational state responsibilities.
* Checkpoint persistence behavior.
* Dead-letter persistence behavior.
* Helm deployment assumptions.
* Kubernetes operational considerations.

### Validation

Documentation was aligned with manually validated deployment scenarios:

* PostgreSQL logical replication.
* Live webhook delivery.
* Retry exhaustion and dead-letter persistence.
* SQLite operational state.
* Helm chart deployment.
* Kind-based Kubernetes deployment.

### Notes

This release focuses on documentation, onboarding, and operational clarity. No runtime or configuration changes were introduced.


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
