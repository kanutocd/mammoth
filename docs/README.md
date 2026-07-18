# Mammoth Documentation

[![Gem Version](https://badge.fury.io/rb/mammoth.svg)](https://badge.fury.io/rb/mammoth)
[![CI](https://github.com/kanutocd/mammoth/workflows/CI/badge.svg)](https://github.com/kanutocd/mammoth/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

🦣 Mammoth is a self-hosted PostgreSQL TransactionEnvelope-driven Change Data Capture relay focused on reliable delivery of database change events to webhook destinations.

```text
PostgreSQL
    ↓
pgoutput-client
    ↓
pgoutput-source-adapter
    ↓
CDC::Core::ChangeEvent / TransactionEnvelope
    ↓
Mammoth
    ↓
Webhook fanout
```

Mammoth is intentionally boring infrastructure. It uses YAML configuration, JSON Schema validation, SQLite-backed operational memory, retries, checkpoints, and dead letters so operators can inspect and recover delivery state.

The source adapter owns incremental PostgreSQL transaction normalization.
Mammoth consumes exact CDC-core work items and does not rebuild transaction
envelopes inside its PostgreSQL composition layer.
Persisted JSON samples and dead letters cross an explicit deserialization
boundary that reconstructs exact core objects before delivery.

## Start here

- [Database Webhooks Quickstart](https://github.com/kanutocd/mammoth/tree/main/webhooks-quickstart)
- [Quick Start](file.QUICK-START.html)
- [Webhook Payloads](file.WEBHOOK-PAYLOADS.html)
- [PostgreSQL](file.POSTGRESQL.html)
- [Configuration](file.CONFIGURATION.html)
- [CLI](file.CLI.html)
- [Benchmarks](file.BENCHMARKS.html)
- [Operational State](file.OPERATIONAL-STATE.html)
- [Observability](file.OBSERVABILITY.html)
- [Extensions](file.EXTENSIONS.html)
- [Examples](file.EXAMPLES.html)
- [Compatibility](file.COMPATIBILITY.html)
- [Helm](file.HELM.html)
- [Troubleshooting](file.TROUBLESHOOTING.html)

The Database Webhooks Quickstart is the recommended first-run experience. One
Docker Compose command starts a demo application, PostgreSQL, Mammoth, and an
inspectable signed webhook receiver with visible retries. Use the documentation
Quick Start when you are ready to assemble those pieces manually.

## v1 Release Scope

Mammoth 1.x supports:

- PostgreSQL logical replication ingestion
- normalized CDC event and transaction delivery to webhooks
- multi-destination webhook fanout
- fanout route filters by schema, table, and operation
- per-destination enable/disable and retry policy controls
- transaction envelope preservation
- concurrent downstream delivery with one PostgreSQL replication stream
- retry handling
- contiguous durable-delivery watermark and PostgreSQL acknowledgement
- source-owned transport LSN preservation independent of payload `commit_lsn`
- fail-closed PostgreSQL slot and checkpoint continuity preflight
- publication replica-identity preflight for `UPDATE` and `DELETE`
- PostgreSQL slot readiness and retained-WAL Prometheus metrics
- SQLite checkpoint storage
- SQLite dead-letter storage
- SQLite delivered-envelope ledger storage
- webhook static headers, env-backed headers, and HMAC-SHA256 signing
- dead-letter inspection and filtered replay commands
- explicit extension registries for state, destination, and runtime adapters
- CDC-core processor results and observer-backed dispatch metrics
- node identity and local capability reporting
- lifecycle hooks, configuration providers, and reusable local command objects
- Docker image distribution
- Helm-based Kubernetes deployment

The supported compatibility boundaries for configuration, webhook payloads,
CLI behavior, and operational-state migrations are documented in
[Compatibility](file.COMPATIBILITY.html).
The canonical event and transaction JSON contracts are documented in
[Webhook Payloads](file.WEBHOOK-PAYLOADS.html).

## v1 Non-goals

Mammoth 1.x does not provide:

- a web dashboard
- multiple active consumers for the same PostgreSQL replication slot
- DDL or sequence replication
- destination-side semantic conflict resolution
- a global exactly-once guarantee across independent operational-state stores

These are explicit product boundaries rather than indicators of pre-production
status.
