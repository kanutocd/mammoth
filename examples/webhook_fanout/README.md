# Mammoth Webhook Fanout Configuration Example

This example demonstrates the 0.5.1 `destinations` configuration shape for
multi-destination webhook fanout.

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
- env-backed Authorization headers
- env-backed HMAC signing secrets

`header_env` and `signing.secret_env` are environment variable names. The
actual token and signing secret must come from the Mammoth process environment,
or from Kubernetes Secrets when using the Helm chart.

## Validate

```bash
bundle exec ./exe/mammoth validate examples/webhook_fanout/config/mammoth.yml
```

