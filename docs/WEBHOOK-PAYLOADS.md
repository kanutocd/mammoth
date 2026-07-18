# Webhook Payloads

Mammoth delivers normalized CDC work as JSON over HTTP. The payload is either
one row-level change event or one transaction envelope containing all row
changes committed by a PostgreSQL transaction.

These serialized forms are supported v1 contracts. Receivers must tolerate
additive fields and additive columns inside `data`, `identity`, `changes`, and
`metadata`.

## Row-level event

With `delivery.unit: event`, Mammoth sends one payload per
`CDC::Core::ChangeEvent`:

```json
{
  "event_id": "evt_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "source": "pgoutput",
  "operation": "update",
  "namespace": "public",
  "entity": "orders",
  "identity": {
    "id": 4
  },
  "source_position": "0/1990620",
  "transaction_id": 765,
  "occurred_at": "2026-07-18T14:34:39Z",
  "data": {
    "id": 4,
    "status": "paid",
    "total_cents": 4999
  },
  "changes": [
    {
      "name": "status",
      "old_value": "pending",
      "new_value": "paid"
    }
  ],
  "metadata": {
    "source": "pgoutput",
    "relation_id": 16386,
    "pgoutput_event": "Update"
  }
}
```

| Field | Meaning |
| --- | --- |
| `event_id` | Stable, opaque idempotency key for this normalized event. |
| `source` | Source adapter label, normally `pgoutput` for live PostgreSQL delivery. |
| `operation` | `insert`, `update`, or `delete`. |
| `namespace` | PostgreSQL schema name. |
| `entity` | PostgreSQL table name. |
| `identity` | Replica-identity columns and values for the affected row, or `null` when unavailable. |
| `source_position` | Source-provided commit/WAL position associated with the event, or `null`. |
| `transaction_id` | Source transaction identifier, or `null`. |
| `occurred_at` | Source event time when available; otherwise Mammoth's serialization time. |
| `data` | New row values for inserts and updates; old row values for deletes. |
| `changes` | Column differences using the canonical shape below. Always an array for supported payloads. |
| `metadata` | Additive source-specific context. |

## Transaction envelope

With the recommended `delivery.unit: transaction`, Mammoth sends one
`transaction.committed` envelope:

```json
{
  "event_id": "txn_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "type": "transaction.committed",
  "source": "pgoutput",
  "transaction_id": 765,
  "source_position": "0/1990628",
  "commit_lsn": "0/1990628",
  "committed_at": "2026-07-18T14:34:39Z",
  "event_count": 1,
  "events": [
    {
      "event_id": "evt_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "source": "pgoutput",
      "operation": "update",
      "namespace": "public",
      "entity": "orders",
      "identity": {
        "id": 4
      },
      "source_position": "0/1990620",
      "transaction_id": 765,
      "occurred_at": "2026-07-18T14:34:39Z",
      "data": {
        "id": 4,
        "status": "paid",
        "total_cents": 4999
      },
      "changes": [
        {
          "name": "status",
          "old_value": "pending",
          "new_value": "paid"
        }
      ],
      "metadata": {
        "source": "pgoutput",
        "relation_id": 16386,
        "pgoutput_event": "Update"
      }
    }
  ],
  "metadata": {
    "source": "pgoutput",
    "pgoutput_event": "Commit"
  }
}
```

| Field | Meaning |
| --- | --- |
| `event_id` | Stable, opaque idempotency key for the committed transaction envelope. |
| `type` | Always `transaction.committed`. |
| `source` | Source label from the first event, or Mammoth's PostgreSQL default. |
| `transaction_id` | Source transaction identifier. |
| `source_position` | Envelope commit position, falling back to the last event position. |
| `commit_lsn` | Same resolved commit position as `source_position`. |
| `committed_at` | Source commit time when available; otherwise Mammoth's serialization time. |
| `event_count` | Number of entries in `events`. |
| `events` | Ordered row-level event payloads in the committed transaction. |
| `metadata` | Additive transaction/source context. |

Use the envelope `event_id` to deduplicate transaction-level side effects.
Use a child event's `event_id` only when applying each row event independently.
Persist the idempotency key atomically with the destination's business
mutation.

## Column changes

Each computed entry has this shape:

```json
{
  "name": "status",
  "old_value": "pending",
  "new_value": "paid"
}
```

Unchanged columns are omitted. The operation determines the meaning:

| Operation | `changes` behavior |
| --- | --- |
| `insert` | One entry per available inserted column, with `old_value: null`. |
| `update` | One entry per changed column when complete old and new rows are available. |
| `delete` | One entry per available deleted column, with `new_value: null`. |

PostgreSQL normally supplies only replica-identity columns from the old row for
an update. Mammoth does not infer differences from that incomplete comparison,
because doing so would produce false `null`-to-value changes. In that case,
`changes` is:

```json
[]
```

For an update, an empty array can therefore mean either:

- column differences were unavailable because PostgreSQL did not provide
  complete old and new rows; or
- complete rows were available but no values differed.

Consumers that must distinguish those cases should configure the table with
`REPLICA IDENTITY FULL` and account for its increased WAL volume and exposure
of previous column values:

```sql
ALTER TABLE public.orders REPLICA IDENTITY FULL;
```

Use `REPLICA IDENTITY DEFAULT` to opt out when current row state in `data` is
sufficient:

```sql
ALTER TABLE public.orders REPLICA IDENTITY DEFAULT;
```

Persisted payload replay preserves an existing explicit `changes` array.
An explicit `null` metadata value is normalized to an empty array; when no
explicit value exists, Mammoth computes changes from the available row images
using the rules above.

## Event IDs

If normalized metadata supplies an `event_id`, Mammoth preserves it. Otherwise,
Mammoth generates deterministic SHA-256 fallback IDs:

```text
evt_<64 lowercase hexadecimal characters>
txn_<64 lowercase hexadecimal characters>
```

The event fallback incorporates stable normalized CDC context, including the
source, transaction and source positions, event sequence and time when
available, schema, table, operation, row identity, and before/after values. The
transaction fallback incorporates transaction context and the ordered child
event IDs. Re-serializing the same normalized work therefore produces the same
fallback ID, preserving retry and restart idempotency.

Treat IDs as opaque strings:

- do not parse the prefix or digest;
- do not reproduce Mammoth's hashing algorithm in a receiver;
- do not assume every ID is a UUID or a Mammoth-generated digest; and
- use an appropriate domain key instead when idempotency represents a business
  operation rather than one exact CDC event.

Mammoth provides at-least-once HTTP delivery, not global exactly-once effects.
Independent operational-state stores and explicit operator replay can submit
the same payload, so destination-side atomic deduplication remains required.

## Payload evolution

Mammoth 1.x does not remove established fields or change their documented types
and meanings incompatibly. Minor releases may add fields. PostgreSQL-derived
columns are controlled by the source schema and are not frozen by Mammoth's
version.

See [Compatibility](file.COMPATIBILITY.html) for the complete v1 promise and
[PostgreSQL](file.POSTGRESQL.html) for replica identity, schema evolution, and
slot continuity requirements.
