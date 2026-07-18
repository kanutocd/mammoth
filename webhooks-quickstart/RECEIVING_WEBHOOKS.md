# Receive Mammoth Webhooks Safely

The Event Console is an inspectable reference receiver. It verifies
authorization and the Mammoth HMAC signature before parsing JSON, records each
attempt, and returns a controlled status. A production receiver should add
atomic idempotency around its business side effect.

## Request contract

The quickstart config sends:

```text
Authorization: <value from MAMMOTH_WEBHOOK_AUTHORIZATION>
X-Mammoth-Timestamp: 2026-07-18T12:34:56Z
X-Mammoth-Signature: sha256=<hex digest>
Content-Type: application/json
```

The signature is:

```text
HMAC-SHA256(secret, timestamp + "." + exact_raw_request_body)
```

Verify the signature before parsing or re-serializing the body. Use a
constant-time comparison and reject timestamps outside a short acceptance
window.

## Transaction payload

The quickstart uses `delivery.unit: transaction`, so one committed transaction
arrives as one envelope:

```json
{
  "event_id": "stable-delivery-id",
  "type": "transaction.committed",
  "transaction_id": "1234",
  "source_position": "0/16B6C50",
  "event_count": 1,
  "events": [
    {
      "event_id": "stable-row-event-id",
      "operation": "update",
      "namespace": "public",
      "entity": "orders",
      "identity": {"id": "42"},
      "data": {"id": "42", "status": "paid"},
      "changes": [
        {
          "name": "status",
          "old_value": "pending",
          "new_value": "paid"
        }
      ]
    }
  ]
}
```

Consumers must tolerate additive top-level, event, metadata, and row fields.

`changes` contains accurate before/after differences only when PostgreSQL
provides a complete old row. The quickstart enables `REPLICA IDENTITY FULL` for
that reason. With `DEFAULT` or index replica identity, consumers should use
`data` as the current row and treat an empty `changes` array as unavailable
column-level history.

## Atomic idempotency

Mammoth provides at-least-once HTTP delivery. A network failure can occur after
the receiver commits a side effect but before Mammoth sees the HTTP response.
Deduplicate at the receiver using the envelope's `event_id`.

A PostgreSQL receiver can use:

```sql
CREATE TABLE processed_mammoth_webhooks (
  event_id TEXT PRIMARY KEY,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Then perform the claim and business change in one transaction:

```ruby
database.transaction do |connection|
  claimed = connection.exec_params(
    <<~SQL,
      INSERT INTO processed_mammoth_webhooks (event_id)
      VALUES ($1)
      ON CONFLICT DO NOTHING
      RETURNING event_id
    SQL
    [payload.fetch("event_id")]
  )

  next if claimed.ntuples.zero? # Duplicate delivery: return HTTP 200.

  payload.fetch("events").each do |event|
    apply_business_change(connection, event)
  end
end
```

The idempotency claim and side effect must commit together. An in-memory set or
a separate non-transactional check is not sufficient.

## Dispatch events explicitly

Use an allowlist of expected tables and operations:

```ruby
def apply_business_change(connection, event)
  case [event.fetch("namespace"), event.fetch("entity"), event.fetch("operation")]
  when ["public", "orders", "insert"], ["public", "orders", "update"]
    sync_order(connection, event.fetch("identity"), event.fetch("data"))
  when ["public", "orders", "delete"]
    remove_order(connection, event.fetch("identity"))
  else
    raise "unsupported Mammoth event route"
  end
end
```

Return HTTP 2xx for accepted events and already-processed duplicates. Return a
non-2xx status only when retrying the exact payload can succeed. Permanent
validation or semantic failures will otherwise retry until they become dead
letters.

## Signature verification in Ruby

The core used by the Event Console is:

```ruby
timestamp = request.get_header("HTTP_X_MAMMOTH_TIMESTAMP")
provided = request.get_header("HTTP_X_MAMMOTH_SIGNATURE")
expected_digest = OpenSSL::HMAC.hexdigest(
  "SHA256",
  ENV.fetch("MAMMOTH_WEBHOOK_SIGNING_SECRET"),
  "#{timestamp}.#{raw_body}"
)
expected = "sha256=#{expected_digest}"

authorized = Rack::Utils.secure_compare(provided, expected)
```

Also validate the authorization header, timestamp format, timestamp age, body
size, and content type before performing side effects.
