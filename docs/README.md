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

- [Quick Start](file.QUICK-START.html)
- [PostgreSQL](file.POSTGRESQL.html)
- [Configuration](file.CONFIGURATION.html)
- [CLI](file.CLI.html)
- [Benchmarks](file.BENCHMARKS.html)
- [Operational State](file.OPERATIONAL-STATE.html)
- [Observability](file.OBSERVABILITY.html)
- [Extensions](file.EXTENSIONS.html)
- [Examples](file.EXAMPLES.html)
- [Helm](file.HELM.html)
- [Troubleshooting](file.TROUBLESHOOTING.html)

## Current release scope

Mammoth 0.8.x focuses on:

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

## Non-goals for 0.8.x

Mammoth 0.8.x does not provide:

- a web dashboard
- multiple active consumers for the same PostgreSQL replication slot

Those are future operational layers.
