# Mammoth Webhook Fanout Configuration Example

This example demonstrates the 0.7.0 `destinations` configuration shape for
multi-destination webhook fanout with operational routing controls.

```text
CDC work item
      ↓
Mammoth
      ↓
primary_webhook + audit_webhook
```

It is intentionally config-only. Use it as a reference when replacing the
single `webhook` shorthand with OSS fanout.

## What It Shows

- two webhook destinations
- independent destination names for ledgers and dead letters
- destination enable/disable knobs
- route filters by schema, table, and operation
- per-destination retry overrides
- env-backed Authorization headers
- env-backed HMAC signing secrets

`header_env` and `signing.secret_env` are environment variable names. The
actual token and signing secret must come from the Mammoth process environment,
or from Kubernetes Secrets when using the Helm chart.

For transaction delivery, route filters match when any event in the transaction
matches. Mammoth still delivers the full transaction envelope to preserve
downstream transaction context.

## Validate

```bash
bundle exec ./exe/mammoth validate examples/webhook_fanout/config/mammoth.yml
```
