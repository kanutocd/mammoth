# Mammoth Live PostgreSQL → Webhook Demo

This example shows the intended live production shape:

```text
PostgreSQL logical replication
      ↓
CDC Ecosystem source adapter
      ↓
Mammoth
      ↓
Webhook receiver
```

Unlike `examples/postgres_webhook`, this example runs `mammoth start` and expects
Mammoth's live CDC source to connect to PostgreSQL.

## Run

```bash
docker compose up --build
```

The compose file starts:

- PostgreSQL with `wal_level=logical`
- a simple Ruby webhook receiver
- Mammoth running `start`
- a small SQL producer that inserts sample orders

## Operational note

Logical replication slots allow one active subscriber per slot. The example uses
one Mammoth process and one replication slot named `mammoth_live`. Mammoth
persists its contiguous delivery watermark before acknowledging that position
through pgoutput-client.
Before streaming, Mammoth preflights the retained slot and fails closed if the
slot cannot serve its configured or persisted resume position.
