# Mammoth PostgreSQL → Webhook Demo

This demo exercises the current Mammoth v0.1.0 vertical slice:

```text
sample PostgreSQL-style event
      ↓
Mammoth delivery runtime
      ↓
Webhook receiver
      ↓
SQLite checkpoint
```

The real pgoutput replication source remains behind `Mammoth::ReplicationConsumer` and is wired in a later milestone. This demo intentionally uses `deliver-sample` so the delivery, checkpoint, and DLQ path can be verified without pretending the PostgreSQL replication adapter is finished.

## Run

```bash
docker compose up --build
```

Expected receiver output:

```text
received demo-order-1 insert orders
```

Mammoth stores operational state in the `.sqlite3/mammoth.db` path inside the `mammoth_data` volume.
