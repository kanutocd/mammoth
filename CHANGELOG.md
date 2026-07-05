# Changelog

## Unreleased

### Added

- Added dead-letter inspection and replay commands for operational recovery.

## 0.2.0

### Added

- Added transaction-level delivery mode using `TransactionEnvelope`.
- Added transaction-aware buffering and aggregation of CDC events.
- Added transaction webhook example demonstrating end-to-end delivery from PostgreSQL logical replication to HTTP webhook.
- Added source position propagation for transaction deliveries.
- Added concurrent delivery runtime integration powered by `cdc-concurrent`.
- Added `DeliveryProcessor` abstraction for runtime execution.
- Added `TransactionEnvelopeSerializer` for transaction payload serialization.
- Added rich self-documenting YAML configuration examples.
- Added configurable webhook HTTP headers through `webhook.headers`.
- Added environment-backed webhook headers through `webhook.header_env` for secrets such as bearer tokens.
- Added optional HMAC-SHA256 webhook request signing through `webhook.signing`.
- Added E2E coverage for duplicate delivery suppression, transaction webhook payloads, dead-letter persistence, and signed/authenticated webhook requests.
- Added Helm chart rendering for delivery runtime, webhook auth headers, signing, and secret-backed webhook environment values.

### Changed

- Transaction delivery now emits a single webhook payload per committed PostgreSQL transaction.
- CDC events belonging to the same database transaction are now grouped into a single `TransactionEnvelope`.
- Delivery pipeline now preserves transaction boundaries from ingestion through webhook delivery.
- Replication slot creation now correctly honors configured temporary/permanent slot settings.
- Concurrent runtime integration now complies with `cdc-concurrent` processor safety requirements.
- Webhook delivery now applies configured static headers, env-backed headers, and per-request signature headers before sending payloads.

### Fixed

- Fixed transaction delivery incorrectly emitting one transaction payload per CDC event.
- Fixed missing source position metadata in transaction deliveries.
- Fixed replication slot option handling for boolean configuration values.
- Fixed transaction webhook example startup and producer execution flow.
- Fixed `cdc-concurrent` runtime compatibility and processor validation failures.
- Fixed quality gate drift by restoring passing coverage, RuboCop, Steep, and YARD validation.

### Examples

- Added `examples/transaction_webhook` demonstrating:

  - PostgreSQL logical replication
  - TransactionEnvelope aggregation
  - Transaction-level webhook delivery
  - Source position propagation
  - Concurrent delivery runtime integration

### Internal

- Established the foundation for transaction-aware checkpointing.
- Established the foundation for ordering policies based on transaction boundaries.
- Established the foundation for future multi-destination fanout delivery.
- Added real `cdc-concurrent` runtime coverage outside the unit-test fake runtime.


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
