# Mammoth Documentation

[![Gem Version](https://badge.fury.io/rb/mammoth.svg)](https://badge.fury.io/rb/mammoth)
[![CI](https://github.com/kanutocd/mammoth/workflows/CI/badge.svg)](https://github.com/kanutocd/mammoth/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

🦣 Mammoth is a self-hosted PostgreSQL TransactionEnvelope-driven Change Data Capture relay focused on reliable delivery of database change events to webhooks.

```text
PostgreSQL
    ↓
pgoutput-client
    ↓
pgoutput-source-adapter
    ↓
CDC::Core::ChangeEvent
    ↓
CDC::Core::TransactionEnvelope
    ↓
Mammoth
    ↓
Webhook
```

Mammoth is intentionally boring infrastructure. It uses YAML configuration, JSON Schema validation, SQLite-backed operational memory, retries, checkpoints, and dead letters so operators can inspect and recover delivery state.

## Start here

- [Quick Start](file.QUICK-START.html)
- [PostgreSQL](file.POSTGRESQL.html)
- [Configuration](file.CONFIGURATION.html)
- [CLI](file.CLI.html)
- [Benchmarks](file.BENCHMARKS.html)
- [Operational State](file.OPERATIONAL-STATE.html)
- [Examples](file.EXAMPLES.html)
- [Helm](file.HELM.html)
- [Troubleshooting](file.TROUBLESHOOTING.html)

## Current release scope

Mammoth 0.2.x focuses on:

- PostgreSQL logical replication ingestion
- normalized CDC event and transaction delivery to webhooks
- transaction envelope preservation
- concurrent downstream delivery with one PostgreSQL replication stream
- retry handling
- SQLite checkpoint storage
- SQLite dead-letter storage
- SQLite delivered-envelope ledger storage
- webhook static headers, env-backed headers, and HMAC-SHA256 signing
- dead-letter inspection and replay commands
- Docker image distribution
- Helm-based Kubernetes deployment

## Non-goals for 0.2.x

Mammoth 0.2.x does not yet provide:

- a web dashboard
- health or metrics HTTP endpoints
- multi-destination routing
- multiple active consumers for the same PostgreSQL replication slot

Those are future operational layers.
