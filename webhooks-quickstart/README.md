# Mammoth Database Webhooks Quick Start

Add reliable, signed webhooks to a PostgreSQL-backed application with one
Docker Compose command.

```bash
cd webhooks-quickstart
docker compose up --build --wait
```

Then open:

- Demo Store: http://localhost:3000
- Webhook Event Console: http://localhost:4000
- Mammoth readiness: http://localhost:9393/readyz
- Mammoth metrics: http://localhost:9393/metrics
- PostgreSQL: `localhost:54331`

Create, update, or cancel a pending order. The Event Console will show the
committed `INSERT`, `UPDATE`, or `DELETE` transaction, its before/after column
changes, its verified signature, and every HTTP delivery attempt.

Paying an order demonstrates a multi-event commit. The Demo Store atomically
updates the order and inserts a captured payment; Mammoth delivers both changes
in one transaction envelope with `event_count: 2`.

Cancelling a paid order demonstrates an accounting reversal without deleting
history. The Demo Store atomically marks the order cancelled and appends an
equal negative `reversed` payment entry. Mammoth again delivers both changes in
one transaction envelope with `event_count: 2`.

## What this demonstrates

The Demo Store performs ordinary transactional `INSERT`, `UPDATE`, and `DELETE`
statements against PostgreSQL. It contains no Mammoth client, callbacks,
publisher, or webhook worker.

```text
Browser → Demo Store → PostgreSQL
                         ↓ logical replication
                       Mammoth
                         ↓ signed, retried HTTP delivery
                    Webhook Event Console
```

The complete Mammoth integration is the Compose service plus
[`mammoth/mammoth.yml`](./mammoth/mammoth.yml). To apply the same pattern to an
existing application, follow [`ADAPTING.md`](./ADAPTING.md). To build a safe
receiver, including signature verification and idempotency, follow
[`RECEIVING_WEBHOOKS.md`](./RECEIVING_WEBHOOKS.md).

The demo table uses `REPLICA IDENTITY FULL` so PostgreSQL supplies complete
before/after rows and Mammoth can identify changed columns accurately. This
increases WAL volume and may expose previous values. See
[`ADAPTING.md`](./ADAPTING.md#column-level-changes-and-opting-out) before using
that setting in production.

The quickstart also limits WAL retained by an unavailable replication consumer
to `1GB`. Override it without editing Compose:

```bash
POSTGRES_MAX_SLOT_WAL_KEEP_SIZE=5GB docker compose up --build --wait
```

This disk-safety guardrail can invalidate the replication slot if Mammoth is
unavailable long enough to exceed it. Follow
[`WAL-RETENTION.md`](./WAL-RETENTION.md) to understand the tradeoff and manually
test graceful shutdown, abnormal termination, catch-up, and slot invalidation.

## Retry and recovery walkthrough

1. Open the Event Console.
2. Enable **Simulate HTTP 500**.
3. Create or update an order in the Demo Store.
4. Watch the failed attempts accumulate in the delivery timeline.
5. Disable **Simulate HTTP 500**.
6. Watch the same delivery succeed on its next attempt.

The console deliberately records every request, including requests for which it
returned HTTP 500. A production receiver should deduplicate side effects using
the payload's stable `event_id`; the console does not deduplicate because its
purpose is to make retries visible.

## Services

| Service | Purpose | Port |
|---|---|---:|
| `postgres` | PostgreSQL 17 with logical replication | 54331 |
| `postgres-setup` | Idempotently applies the demo schema and replica identity | — |
| `demo-app` | Minimal order-management application | 3000 |
| `event-console` | Signed webhook receiver and retry inspector | 4000 |
| `mammoth-init` | Validates config and bootstraps operational state | — |
| `mammoth` | PostgreSQL change-event relay | — |
| `mammoth-observability` | Health, readiness, and Prometheus metrics | 9393 |

## Automated verification

The smoke test creates, deletes, pays, and reverses real orders, then waits for
the corresponding Mammoth webhooks. It verifies both the captured payment and
negative reversal as two-event transactions:

```bash
./scripts/smoke-test.sh
```

Include retry recovery:

```bash
TEST_RETRY=1 ./scripts/smoke-test.sh
```

This is an end-to-end test of:

```text
HTTP request → application SQL → PostgreSQL WAL → Mammoth → signed webhook
```

## Useful commands

```bash
# Follow Mammoth delivery activity
docker compose logs -f mammoth

# Validate the exact mounted config
docker compose run --rm mammoth-init mammoth validate /config/mammoth.yml

# Inspect Mammoth operational state
docker compose exec mammoth mammoth status /config/mammoth.yml

# Inspect pending dead letters
docker compose exec mammoth \
  mammoth dead-letters list /config/mammoth.yml --status pending

# Inspect the source table
docker compose exec postgres \
  psql -U mammoth -d mammoth_demo -c 'TABLE orders;'

# Inspect the replication slot
docker compose exec postgres \
  psql -U mammoth -d mammoth_demo \
  -c "SELECT slot_name, active, confirmed_flush_lsn, wal_status, safe_wal_size FROM pg_replication_slots;"

# Reset all PostgreSQL, Mammoth, and receiver state
docker compose down -v
rm -f data/events/*
```

## Mammoth image

The Compose file defaults to the released image matching this quickstart:

```text
ghcr.io/kanutocd/mammoth:v1.1.0
```

Override it without editing Compose:

```bash
MAMMOTH_IMAGE=ghcr.io/kanutocd/mammoth:latest \
  docker compose up --build --wait
```

For a locally built image:

```bash
docker build -t mammoth:local ..
MAMMOTH_IMAGE=mammoth:local docker compose up --build --wait
```

The `mammoth-init` service validates configuration against the selected image
before the relay starts. A schema mismatch therefore fails startup with a
specific validation error instead of producing a silent, partially working
demo.

## Local-only security boundary

The stack uses intentionally public demo credentials and ports. It does
demonstrate env-backed authorization and HMAC signing, but its secrets are
checked into Compose for transparency. Do not expose this stack outside
localhost or reuse its credentials. See the production checklist in
[`ADAPTING.md`](./ADAPTING.md#production-checklist).

## Development checks

The example UIs are intentionally split into ordinary source files:

- `demo_app/order_actions.rb` defines the order workflow and confirmation copy,
  `demo_app/views/` contains the ERB templates, and `demo_app/public/` contains
  the Demo Store styles and JavaScript.
- `event_console/views/` contains the Event Console ERB template, and
  `event_console/public/` contains its styles and JavaScript.

WEBrick serves the Rack applications, while Ruby's standard `ERB` library
renders the templates. Edit these files directly, then rebuild the affected
Compose service to see the result.

```bash
bundle exec ./exe/mammoth validate webhooks-quickstart/mammoth/mammoth.yml
ruby -c webhooks-quickstart/demo_app/app.rb
ruby -c webhooks-quickstart/event_console/app.rb
node --check webhooks-quickstart/demo_app/public/app.js
node --check webhooks-quickstart/event_console/public/app.js
sh -n webhooks-quickstart/scripts/smoke-test.sh
docker compose -f webhooks-quickstart/compose.yml config
```
