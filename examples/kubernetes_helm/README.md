# Mammoth Kubernetes / Helm Example

The public Helm chart lives in `charts/mammoth`.

## Render manifests

From the repository root:

```bash
helm template mammoth charts/mammoth \
  --set image.repository=ghcr.io/kanutocd/mammoth \
  --set image.tag=latest
```

## Install

```bash
helm install mammoth charts/mammoth \
  --set image.repository=ghcr.io/kanutocd/mammoth \
  --set image.tag=latest
```

## Persistence

The chart mounts a PVC for Mammoth's SQLite database. SQLite is the built-in
operational-state adapter's storage for checkpoints, dead letters, and the
delivered-envelope ledger.

## Replication slot constraint

Run one active Mammoth replica per logical replication slot. PostgreSQL logical
replication slots are consumed by one active subscriber at a time, so the chart
uses a single replica by default.
Because the PVC retains Mammoth checkpoints, a missing, invalidated, or
checkpoint-unreachable PostgreSQL slot fails startup preflight instead of being
silently recreated.

## Production operations

After first-time bootstrap, prefer a DBA-managed permanent slot with
`replication.auto_create_slot: false`. Treat the slot and Mammoth PVC as one
continuity boundary during restore, migration, and PostgreSQL upgrade.

Alert on Mammoth slot readiness and retained-WAL metrics as well as PostgreSQL
disk capacity and catalog-XID age. Server guardrails such as
`max_slot_wal_keep_size` and, where supported,
`idle_replication_slot_timeout` protect PostgreSQL by invalidating unhealthy
slots; they do not preserve the missing delivery interval. Coordinate schema
migrations with webhook consumers because DDL is not replicated.

The chart defaults `logging.level` to `info`. Mammoth writes
newline-delimited JSON to standard output for collection by the cluster logging
stack:

```bash
kubectl logs -f deployment/mammoth
```

Use `debug` temporarily for per-work and WAL acknowledgement records, or
`warn`/`error` for quieter operation. Logs omit payload bodies, configured
headers, credentials, signing secrets, and exception messages.

The OSS chart starts only `mammoth start`. Run `mammoth observability` as a
separate process with the same configuration, PostgreSQL Secret, and PVC when
the deployment needs `/readyz` and `/metrics`; do not start a second relay for
observability.
