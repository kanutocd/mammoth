# Mammoth Failing Webhook Retry Demo

This example demonstrates Mammoth's reliability behavior when a destination does
not accept delivery. Its sample JSON is reconstructed as an exact
`CDC::Core::ChangeEvent` before entering the delivery pipeline:

```text
sample CDC-shaped event
      ↓
Mammoth delivery worker
      ↓
webhook returns 500
      ↓
retry exhaustion
      ↓
SQLite dead letter
```

## Run

```bash
docker compose up --build
```

The receiver always returns HTTP 500. Mammoth retries according to the example
configuration and then records the failed event as a dead letter.

## Inspect state

The SQLite database is stored in the `mammoth_retry_data` volume at:

```text
/app/.sqlite3/mammoth.db
```
