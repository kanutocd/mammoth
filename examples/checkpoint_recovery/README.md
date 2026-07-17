# Checkpoint Recovery Example

This example demonstrates that Mammoth resumes from persisted checkpoint state
across a process restart.

It proves the operational recovery path:

```text
transaction A
transaction B
        ↓
Mammoth records durable delivery, checkpoints,
and acknowledges contiguous progress
        ↓
Mammoth restarts
        ↓
transaction C
        ↓
Mammoth continues without replaying A/B
```

Expected final receiver state:

```text
delivered=ABC
```

Not:

```text
delivered=ABABC
```

and not:

```text
delivered=AB
```

## Run

Start PostgreSQL, the webhook receiver, and Mammoth:

```bash
docker compose up -d postgres webhook_receiver mammoth
```

Produce two transactions before the restart:

```bash
docker compose run --rm producer_before_restart
```

Check the receiver log:

```bash
docker compose logs webhook_receiver
```

You should see:

```text
delivered=A
delivered=AB
```

Restart Mammoth only:

```bash
docker compose stop mammoth
docker compose start mammoth
```

Produce one more transaction after the restart:

```bash
docker compose run --rm producer_after_restart
```

Inspect the receiver log again:

```bash
docker compose logs webhook_receiver
```

Expected final output includes:

```text
delivered=ABC
```

## Why This Matters

Mammoth stores operational state in SQLite and uses a permanent PostgreSQL
logical replication slot in this example.

The important property is not just that Mammoth restarts. The configured
operational-state adapter persists both checkpoints and the delivered-envelope
ledger, so already delivered transactions are not replayed after restart while
later transactions continue to be delivered. Mammoth writes each contiguous
watermark to SQLite before acknowledging the same position through
pgoutput-client.

On restart, Mammoth preflights the permanent slot before using the SQLite
checkpoint. If PostgreSQL slot state is removed while the SQLite volume is
retained, the example fails closed instead of silently creating a replacement
slot and skipping the lost WAL interval. Reset or reconcile PostgreSQL and
Mammoth operational state together.

## Reset

To remove all PostgreSQL, Mammoth, and receiver state:

```bash
docker compose down -v
```
