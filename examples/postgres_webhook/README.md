# Mammoth Sample Webhook Delivery Demo

This demo exercises the current Mammoth delivery path. The sample JSON is
deserialized into an exact `CDC::Core::ChangeEvent` before delivery:

```text
sample CDC-shaped PostgreSQL event
      ↓
Mammoth delivery runtime
      ↓
Webhook receiver
      ↓
SQLite checkpoint + delivered-envelope ledger
```

This is not a live logical-replication demo. It intentionally uses
`deliver-sample` so webhook delivery, checkpoint persistence, and the delivery
worker can be verified without requiring PostgreSQL replication to be active.
Use [`../live_postgres_webhook`](../live_postgres_webhook) for the full
PostgreSQL → Mammoth → Webhook shape.

## Run

```bash
docker compose up --build
```

Expected receiver output:

```text
received demo-order-1 insert orders
```

Mammoth stores operational state in the `.sqlite3/mammoth.db` path inside the
`mammoth_data` volume. The configured operational-state adapter owns both the
checkpoint store and delivered-envelope ledger used by the delivery worker.
