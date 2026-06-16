# Mammoth Operational State Demo

This example focuses on Mammoth's SQLite operational memory:

- schema bootstrap
- checkpoint table
- dead-letter table
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

Reliable delivery requires durable operational memory. Mammoth uses SQLite to
remember checkpoints, failed deliveries, and replay-related metadata.
