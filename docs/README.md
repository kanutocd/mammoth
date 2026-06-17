# Mammoth Documentation

[![Gem Version](https://badge.fury.io/rb/mammoth.svg)](https://badge.fury.io/rb/mammoth)
[![CI](https://github.com/kanutocd/mammoth/workflows/CI/badge.svg)](https://github.com/kanutocd/mammoth/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

🦣 Mammoth is a self-hosted PostgreSQL Change Data Capture relay focused on reliable delivery of database change events to webhooks.

```text
PostgreSQL
    ↓
pgoutput-client
    ↓
pgoutput-source-adapter
    ↓
CDC::Core::ChangeEvent
    ↓
Mammoth
    ↓
Webhook
```

Mammoth is intentionally boring infrastructure. It uses YAML configuration, JSON Schema validation, SQLite-backed operational memory, retries, checkpoints, and dead letters so operators can inspect and recover delivery state.

## Start here

- [Quick start](quick-start.md)
- [PostgreSQL requirements](postgresql.md)
- [Configuration](configuration.md)
- [CLI reference](cli.md)
- [Operational state](operational-state.md)
- [Examples](examples.md)
- [Kubernetes and Helm](helm.md)
- [Troubleshooting](troubleshooting.md)

## Current release scope

Mammoth 0.1.x focuses on:

- PostgreSQL logical replication ingestion
- normalized CDC event delivery to webhooks
- retry handling
- SQLite checkpoint storage
- SQLite dead-letter storage
- Docker image distribution
- Helm-based Kubernetes deployment

## Non-goals for 0.1.x

Mammoth 0.1.x does not yet provide:

- a web dashboard
- health or metrics HTTP endpoints
- dead-letter replay commands
- multi-destination routing
- multiple active consumers for the same PostgreSQL replication slot

Those are future operational layers.
