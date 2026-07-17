# Destination Idempotency Example

This example proves that destination idempotency is independent of Mammoth's
local delivered-envelope ledger.

Two isolated Mammoth delivery processes, each with its own empty SQLite
operational store, submit the same event to one receiver:

```text
Mammoth ledger A ─┐
                  ├─ same event_id ─→ receiver UNIQUE(event_id) ─→ one side effect
Mammoth ledger B ─┘
```

Both Mammoth processes legitimately send the event because neither can see the
other process's ledger. The receiver records both HTTP attempts but atomically
applies the business side effect only once.

## Run

Start from empty relay and receiver stores:

```bash
docker compose down -v
docker compose build delivery_a delivery_b
docker compose up -d --wait webhook_receiver
docker compose run --rm delivery_a
docker compose run --rm delivery_b
```

Inspect the receiver:

```bash
docker compose logs webhook_receiver
curl -s http://localhost:9301/state
```

The delivery order may vary, but the logs should contain one `applied` and one
`duplicate` result for `order-created-42`. The state endpoint should report:

```json
{
  "delivery_attempts": 2,
  "applied_side_effects": 1,
  "event_ids": ["order-created-42"]
}
```

## Receiver Pattern

The receiver uses `event_id` as its semantic idempotency key and enforces it
with a unique primary key inside the same transaction as the simulated order
side effect. A duplicate returns HTTP 200 because the requested outcome has
already been achieved.

In a real destination, choose a key whose stability matches the business
operation. An event ID is appropriate when repeating the exact event must be a
no-op. Some APIs instead need a domain key such as `(order_id, transition)` or
a caller-provided idempotency key. Persist the key and business mutation
atomically; a separate check followed by an insert has a race.

## Boundary

Mammoth's delivered-envelope ledger suppresses duplicates visible within one
configured operational-state store. It reduces duplicate HTTP delivery but
cannot provide a global exactly-once guarantee across restored state, isolated
stores, operator replay, or other producers.

The destination owns semantic conflict handling and idempotent side effects.
Returning success for an already-applied event lets Mammoth checkpoint or
record the delivery normally. Returning an error for a harmless duplicate
would instead cause retries and potentially a dead letter.

## Run Again

Running only the two delivery services again demonstrates Mammoth's local
ledgers: each process suppresses its own duplicate before making another HTTP
request.

```bash
docker compose run --rm delivery_a
docker compose run --rm delivery_b
curl -s http://localhost:9301/state
```

The receiver state remains at two delivery attempts and one applied side
effect. Use `docker compose down -v` to reset all three independent stores.
