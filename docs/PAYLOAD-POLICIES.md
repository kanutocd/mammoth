# Payload Policies

Mammoth OSS can remove or mask selected PostgreSQL columns before a payload
leaves the data plane. Policies are configured per destination, so one receiver
can receive the complete event while another receives a reduced projection.

Use this boundary to enforce straightforward, deterministic data minimization
close to the source. Mammoth Platform may provide centralized policy authoring,
governance, rollout, and audit workflows, but it is not required to execute an
OSS payload policy.

## Configure a policy

Add `payload_policy` to the single `webhook` shorthand or to an entry under
`destinations`:

```yaml
destinations:
  - name: analytics_webhook
    type: webhook
    url: https://analytics.example.com/cdc
    payload_policy:
      rules:
        - schemas: [public]
          tables: [orders]
          operations: [insert, update]
          columns: [customer_email]
          action: mask
          replacement: "[PRIVATE]"
        - tables: [payments]
          columns: [card_token]
          action: remove
```

Each rule requires:

- `columns`: one or more exact column names; and
- `action`: `remove` or `mask`.

The optional `schemas`, `tables`, and `operations` selectors are
case-insensitive. An omitted selector matches every value. `mask` uses
`[REDACTED]` unless `replacement` is configured.

## What is transformed

Matching columns are handled consistently across every canonical row-value
location:

- `data`;
- `identity`; and
- `changes[].old_value` and `changes[].new_value`.

`remove` deletes the column from `data` and `identity` and removes its
corresponding `changes` entries. `mask` retains the field shape and substitutes
non-null values. Null old/new values remain null so change semantics are not
invented.

For transaction delivery, Mammoth evaluates each child event independently and
keeps the transaction envelope intact. Route matching still evaluates the
canonical payload before projection; removing a field cannot change whether
the destination receives the work.

## Delivery, retry, and replay guarantees

Mammoth prepares the destination payload once. The exact prepared JSON is used
for the HTTP body and HMAC signature on every retry. If delivery exhausts its
retry policy, that same reduced payload—not the original source payload—is
written to the dead-letter store.

Dead-letter replay sends the stored prepared payload unchanged. It does not
reapply the current policy. This prevents an older failure from regaining
removed PII and prevents a later policy edit from silently changing replay
content.

An active policy adds this destination-visible metadata:

```json
{
  "mammoth_payload_policy": {
    "fingerprint": "sha256:..."
  }
}
```

The deterministic fingerprint identifies the policy configuration that
prepared the payload. Treat it as operational evidence, not as a secret or a
substitute for policy-version governance.

## Boundaries and cautions

- Policies are opt-in; configurations without `payload_policy` preserve the
  canonical payload.
- Rules use declarative column matching only. Mammoth does not execute
  arbitrary transformation code.
- Column names may still appear in source metadata supplied by an adapter.
  Review representative payloads before treating a policy as a compliance
  control.
- Destination headers, URLs, errors, and logs are separate exposure surfaces.
- Masking is not encryption or tokenization. Use `remove` when the receiver
  does not need a value.
- Removing replica-identity fields can make destination-side row correlation
  impossible. Keep the business or idempotency keys the receiver needs.

Validate every change before deployment:

```bash
mammoth validate config/mammoth.yml
```

Then exercise insert, update, delete, retry, and dead-letter replay paths
against a non-production receiver.
