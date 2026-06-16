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

The chart mounts a PVC for Mammoth's SQLite database. SQLite is Mammoth's
operational memory for checkpoints, dead letters, and replay metadata.

## Replication slot constraint

Run one active Mammoth replica per logical replication slot. PostgreSQL logical
replication slots are consumed by one active subscriber at a time, so the chart
uses a single replica by default.
