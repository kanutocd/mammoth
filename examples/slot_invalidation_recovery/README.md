# Slot Invalidation Recovery Example

This example demonstrates what happens when PostgreSQL invalidates a logical
replication slot after it goes idle and how recovery must be handled outside
Mammoth's transport boundary.

```text
transaction A
      ↓
Mammoth delivers A and checkpoints the durable watermark
      ↓
Mammoth stops
      ↓
PostgreSQL invalidates the idle slot under WAL pressure
      ↓
Mammoth restarts and fails closed on the invalidated slot
      ↓
operator drops the invalidated slot and clears Mammoth's checkpoint
      ↓
Mammoth starts fresh and auto-creates a safe replacement slot
      ↓
transaction B
      ↓
Mammoth delivers B on the new safe baseline
```

Expected receiver output:

```text
delivered=A
delivered=AB
```

Not:

```text
delivered=ABA
```

and not an automatic resume across the invalidated interval.

## Run

Start PostgreSQL, the webhook receiver, and Mammoth:

```bash
docker compose up -d postgres webhook_receiver mammoth
```

Produce the first transaction:

```bash
docker compose run --rm producer_before_invalidation
```

Check the receiver log:

```bash
docker compose logs webhook_receiver
```

You should see:

```text
delivered=A
```

Stop Mammoth so the slot can go idle:

```bash
docker compose stop mammoth
```

Generate enough additional WAL to force invalidation of the inactive slot:

```bash
docker compose run --rm wal_churn
```

Start Mammoth again. It should fail closed because the slot is invalidated:

```bash
docker compose up -d mammoth
docker compose logs mammoth
```

Recover by dropping the invalidated slot and clearing Mammoth's checkpoint
state:

```bash
docker compose run --rm operator_reconcile
```

Start Mammoth again on a fresh safe baseline:

```bash
docker compose up -d mammoth
```

Produce the second transaction after recovery:

```bash
docker compose run --rm producer_after_recovery
```

Inspect the receiver log again:

```bash
docker compose logs webhook_receiver
```

Expected final output includes:

```text
delivered=AB
```

## What This Demonstrates

Mammoth preflights the configured slot before streaming. If PostgreSQL reports
that the slot is invalidated, Mammoth fails closed rather than pretending the
old checkpoint still has continuity.

Recovery is an operator action: drop the invalidated slot, clear Mammoth's
durable checkpoint state, and then restart from a fresh safe baseline so a new
slot can be created. That keeps lost WAL continuity out of the transport
client's responsibility.

## Reset

To remove all PostgreSQL, Mammoth, and receiver state:

```bash
docker compose down -v
```
