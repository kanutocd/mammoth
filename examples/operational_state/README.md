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

## Why this matters

Reliable delivery requires durable operational memory. The built-in state
adapter uses SQLite to remember checkpoints, failed deliveries, and delivered
envelopes used for duplicate suppression.
