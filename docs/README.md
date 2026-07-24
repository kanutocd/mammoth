<!--
# @markup markdown
# @title Index
# @author Ken C. Demanawa
-->
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/kanutocd/mammoth/main/docs/branding/logo/exports/png/mammoth-primary-horizontal-reversed-transparent.png">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/kanutocd/mammoth/main/docs/branding/logo/exports/png/mammoth-primary-horizontal-light.png">
    <img src="https://raw.githubusercontent.com/kanutocd/mammoth/main/docs/branding/logo/exports/png/mammoth-primary-horizontal-light.png" alt="Mammoth" width="620">
  </picture>
</p>

# Mammoth Documentation

[![Gem Version](https://img.shields.io/gem/v/mammoth?logo=rubygems&logoColor=white)](https://rubygems.org/gems/mammoth)
[![Requires Ruby 4.0+](https://img.shields.io/badge/Requires-Ruby%204.0%2B-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![CI](https://github.com/kanutocd/mammoth/actions/workflows/ci.yml/badge.svg)](https://github.com/kanutocd/mammoth/actions/workflows/ci.yml)
[![Tested Against PostgreSQL 14–18](https://img.shields.io/badge/Tested%20Against-PostgreSQL%2014--18-336791?logo=postgresql&logoColor=white)](https://github.com/kanutocd/mammoth/blob/main/.github/workflows/ci.yml#L50)
[![License](https://img.shields.io/badge/License-MIT-22C55E)](file.LICENSE.html)

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
Persisted sample JSON crosses an explicit deserialization boundary that
reconstructs exact core work before first delivery. Dead-letter replay instead
sends the exact destination payload already persisted after policy projection;
it does not reconstruct CDC work or reapply the current policy.

## Supported PostgreSQL versions

Mammoth supports PostgreSQL 14 through PostgreSQL 18, inclusive. These are the
PostgreSQL major versions currently maintained by the PostgreSQL community and
covered by Mammoth's real logical-replication E2E compatibility matrix.

Mammoth supports PostgreSQL major versions that are both maintained by the
PostgreSQL community and included in Mammoth's compatibility test matrix. New
PostgreSQL majors are unsupported until explicitly tested and documented. EOL
versions may be removed from the supported range in a subsequent Mammoth minor
release with release-note notice.

PostgreSQL 19 is a development release and is not supported.

## Start here

- [Webhooks Quick Start](https://github.com/kanutocd/mammoth/tree/main/webhooks-quickstart)
- [Quick Start](file.QUICK-START.html)
- [Webhook Payloads](file.WEBHOOK-PAYLOADS.html)
- [Payload Policies](file.PAYLOAD-POLICIES.html)
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
- [Glossary](file.GLOSSARY.html)
- [Troubleshooting](file.TROUBLESHOOTING.html)

The **[Webhooks Quick Start](https://github.com/kanutocd/mammoth/tree/main/webhooks-quickstart)** is the recommended first-run experience. One
Docker Compose command starts a demo application, PostgreSQL, Mammoth, and an
inspectable signed webhook receiver with visible retries and customer-email
masking. Its optional
monitoring profile adds seeded traffic, a provisioned Grafana overview and
alerts, and a curated Prometheus query library. See
[Observability](file.OBSERVABILITY.html) for the runnable monitoring showcase.
Use the documentation Quick Start when you are ready to assemble those pieces
manually.
Released tags use their matching image; when testing Unreleased quickstart
configuration from `main`, build the local image as described in the
quickstart README.

## v1 Release Scope

Mammoth 1.x supports:

- PostgreSQL logical replication ingestion
- normalized CDC event and transaction delivery to webhooks
- multi-destination webhook fanout
- fanout route filters by schema, table, and operation
- per-destination payload removal and masking policies
- per-destination enable/disable and retry policy controls
- transaction envelope preservation
- concurrent downstream delivery with one PostgreSQL replication stream
- retry handling
- configurable structured JSON logging to standard output
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

Mammoth's `logging.level` accepts `debug`, `info`, `warn`, or `error`. Logs are
newline-delimited JSON on standard output so Docker and Kubernetes collect them
directly. `info` is the recommended default; use `debug` temporarily for
per-work and WAL acknowledgement detail. See
[Configuration](file.CONFIGURATION.html#logging) for the logged events and
sensitive-data boundary.

## v1 Non-goals

Mammoth 1.x does not provide:

- a web dashboard
- multiple active consumers for the same PostgreSQL replication slot
- DDL or sequence replication
- destination-side semantic conflict resolution
- a global exactly-once guarantee across independent operational-state stores

These are explicit product boundaries rather than indicators of pre-production
status.
