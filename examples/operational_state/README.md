# Mammoth Operational State Demo

This example focuses on Mammoth's SQLite operational memory:

- schema bootstrap
- checkpoint table
- dead-letter table
- delivered-envelope ledger table
- status command

It is useful when you want to inspect the local database shape without running
PostgreSQL or an HTTP receiver.

## Run locally

From the repository root:

```bash
bundle exec ./exe/mammoth bootstrap examples/operational_state/config/mammoth.yml
bundle exec ./exe/mammoth status examples/operational_state/config/mammoth.yml
```

Mammoth creates the SQLite database at:

```text
examples/operational_state/.sqlite3/mammoth.db
```

Both commands resolve `operational_state.adapter` and operate through that
adapter contract. SQLite paths and tables are reported by the built-in adapter's
summary rather than assumed by the commands.

The adapter-backed checkpoint, dead-letter, and delivered-envelope metrics can
be inspected from a separate observability process. Dispatch lifecycle counters
are different: they are recorded by `Mammoth::MetricsObserver` in the relay
process using the canonical `CDC::Core::Observer` contract. The separate
process also performs read-only PostgreSQL slot inspection for readiness and
retained-WAL gauges.

## Why this matters

Reliable delivery requires durable operational memory. The built-in state
adapter uses SQLite to remember checkpoints, failed deliveries, and delivered
envelopes used for duplicate suppression.
