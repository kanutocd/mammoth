# Changelog

## Unreleased

### Added

- Added PostgreSQL slot readiness diagnostics and Prometheus gauges for
  inspection availability, presence, activity, retained WAL bytes, safe WAL
  size, WAL status, invalidation, inactivity time, and restart/flush LSNs.
- `/readyz` now fails closed when the configured slot is missing, inactive,
  invalidated, conflicting, WAL-lost, or cannot be inspected.
- Added startup validation for every configured publication table that publishes
  `UPDATE` or `DELETE`, accepting a usable primary key, selected replica-identity
  index, or `REPLICA IDENTITY FULL` and reporting all invalid tables together.
- Added catalog-derived, ordered replica-identity mappings for relation OIDs and
  schema-qualified tables.
- Added a self-verifying live PostgreSQL example for composite, non-`id`
  replica identities across `INSERT`, `UPDATE`, and `DELETE`.
- Added a live PostgreSQL example that shows fail-closed restart after slot
  invalidation and the explicit operator reconciliation required to resume.
- Added a PostgreSQL observability example correlating Mammoth readiness and
  Prometheus slot gauges with native replication and publication catalogs.
- Added a live additive schema-evolution example demonstrating consumer-first
  compatibility, relation-metadata refresh, and the non-delivery of DDL.

### Fixed

- Added PostgreSQL slot preflight before streaming and fail-closed handling for
  missing, active, lost, invalidated, incompatible, and
  checkpoint-unreachable slots.
- Disabled automatic slot recreation whenever a configured or persisted resume
  LSN requires WAL continuity.
- Rejected temporary-slot recovery from durable checkpoints.
- Preserved pgoutput-client's acknowledgement-compatible transport LSN
  separately from normalized CDC-core `commit_lsn` payload context.
- Checkpoints and PostgreSQL feedback now use the source-owned transport
  watermark, preventing decimal transaction commit values from reaching
  `runner.ack`.
- Event-mode delivery resolves an envelope's transport position for each exact
  child event without mutating or rebuilding CDC-core work.
- Wired publication identity mappings into
  `Pgoutput::SourceAdapter::ReplicaIdentityResolver` so composite and non-`id`
  keys are normalized without partial identity data.

### Quality

- Upgraded pgoutput-client to 0.4.0 and covered slot identity, health,
  retained-WAL reporting, continuity boundaries, and safe first-time creation.
- Upgraded pgoutput-source-adapter to 0.3.0 and covered catalog-to-resolver
  composition for composite replica identities.
- Upgraded pgoutput-decoder to 0.2.0 so key-only old tuples preserve their
  exact decoded columns instead of synthesizing absent non-key values.
- Added end-to-end source/coordinator coverage proving that a transaction with
  decimal `commit_lsn` checkpoints and acknowledges its formatted transport LSN.
- Added opt-in PostgreSQL 17 integration coverage for transactional `INSERT`,
  `UPDATE`, and `DELETE` with composite identity, replication reconnects,
  concurrent out-of-order completion, contiguous slot acknowledgement, and
  fail-closed slot invalidation; CI and release gates run the suite against a
  logical-replication service.
- Strengthened boundary coverage for source-owned position resolution and
  publication-catalog inspection, and synchronized PostgreSQL, runtime,
  operational-state, configuration, and transaction-example documentation.
- Documented PostgreSQL WAL guardrails, slot/catalog monitoring, DDL and
  sequence limitations, destination conflict ownership, upgrade recovery,
  troubleshooting, example caveats, and Kubernetes deployment policy.

## 0.9.0

### Changed

- Refactored observability, status, bootstrap, and dead-letter command
  composition to consume `OperationalState::Adapter` instead of opening SQLite
  or constructing concrete stores.
- Added adapter-owned `bootstrap!`, `ready?`, and configured registry
  composition for backend-neutral operational tooling.
- Inject the configured operational-state delivered-envelope store into every
  delivery worker instead of deriving a SQLite ledger from the checkpoint store.
- Made `Mammoth::DeliveryProcessor` implement `CDC::Core::Processor` and return
  `CDC::Core::ProcessorResult` for successful, skipped, and failed deliveries.
- Wired `CDC::Core::Observer` notifications through inline and concurrent
  runtimes and translated canonical dispatch metrics into Mammoth Prometheus
  counters.
- Replaced duck-typed CDC lookalikes with exact `CDC::Core::ChangeEvent` and
  `CDC::Core::TransactionEnvelope` objects.
- Enforced the PostgreSQL source output contract by rejecting non-core work
  yielded by injected source adapters.
- Added an explicit persisted-payload deserialization boundary for sample JSON
  and dead-letter replay.
- Moved configured batch accumulation and final partial-batch submission out of
  `Mammoth::Application` and into the delivery runtime layer.

### Quality

- Added processor contract, observer, runtime notification, dispatch counter,
  and Prometheus exposition coverage.
- Added exact core-type and persisted-payload round-trip coverage.
- Strengthened architecture boundary coverage with executable pgoutput adapter
  output checks, downstream dependency guards, and an exact core-output RBS
  contract for the PostgreSQL source.
- Added runtime batching ownership coverage so application orchestration cannot
  reintroduce buffering or batch partitioning.
- Updated RBS signatures, YARD API documentation, examples, and benchmark
  descriptions for the corrected processor/observer boundary.

## 0.8.0

### Changed

- Delegated incremental PostgreSQL transaction buffering and
  `CDC::Core::TransactionEnvelope` construction to `pgoutput-source-adapter`.
- `Mammoth::Sources::Postgres` now streams decoded events and transport WAL
  positions through the adapter's `each_normalized` API instead of maintaining
  private transaction state or envelope lookalikes.

### Quality

- Added boundary and source integration coverage for streaming adapter
  delegation, exact core envelope preservation, and WAL position forwarding.
- Updated API signatures, examples, benchmark descriptions, and architecture
  documentation for the corrected source-adapter boundary.

## 0.7.2

### Changed

- Elevated webrick to be a runtime dependency as the default observability http server

## 0.7.1

### Added

- Added local lifecycle hooks for start, shutdown, and dead-letter replay extension points.
- Added file and hash configuration providers for CLI, tests, and future control-plane integration.
- Added reusable command objects for validate, bootstrap, start, sample delivery, and dead-letter commands.

### Changed

- Bumped Mammoth version to `0.7.1`.

## 0.7.0

### Added

- Added explicit adapter registries for operational state, destinations, and delivery runtimes.
- Added the built-in SQLite operational state adapter.
- Added the built-in webhook destination adapter registration.
- Added inline and concurrent runtime adapter registration.
- Added optional node identity configuration for future control-plane integration.
- Added local capability reporting for state, destination, runtime, and relay features.
- Added a reusable status command object behind the CLI status command.

### Changed

- Bumped Mammoth version to `0.7.0`.

## 0.6.0

### Added

- Added fanout route filters by schema, table, and operation for webhook destinations.
- Added destination `enabled` controls for config-driven delivery cutovers.
- Added per-destination retry policy overrides for `max_attempts` and `schedule_seconds`.
- Added dead-letter replay filters by destination, status, and failed-at time window.
- Added destination-labeled Prometheus metrics for dead-letter and delivered-envelope counts.

### Changed

- Bumped Mammoth version to `0.6.0`.

## 0.5.1

### Added

- Added benchmark scripts for webhook delivery, webhook fanout, SQLite operational state, observability snapshots, and dead-letter replay.
- Added shared benchmark helpers for synthetic CDC work items, local HTTP receivers, table output, JSON output, and environment-driven benchmark knobs.
- Added a benchmark snapshot runner that writes Markdown, JSON, and per-trial logs for publishable benchmark results.

### Changed

- Aligned benchmark documentation across `README.md`, `docs/BENCHMARKS.md`, and `benchmark/README.md` around operator config tuning.

## 0.5.0

### Added

- Added multi-destination webhook fanout through `destinations`, with independent per-destination retry, delivered-ledger, and dead-letter state.
- Added targeted fanout dead-letter replay so replay sends failed work back only to the original destination.
- Added Helm rendering for fanout destinations, including secret-backed environment variables for Authorization headers and HMAC signing secrets.

## 0.4.0

### Added

- Added optional observability support with `/healthz`, `/readyz`, and `/metrics` endpoints, plus CLI startup, configuration, and documentation coverage.

## 0.4.0

### Added

- Added dead-letter inspection and replay commands for operational recovery.
- Added dead-letter support for list, show, and replay, with replay routing both event and transaction dead letters back through the existing delivery path and resolving successful rows


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
