# Kubernetes and Helm

The public Helm chart lives in:

```text
charts/mammoth
```

## Render manifests

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

## Required external resources

The chart deploys Mammoth. It does not create your full CDC environment.

You must provide:

- PostgreSQL reachable from the cluster
- PostgreSQL logical replication settings
- publication
- replication slot or `auto_create_slot: true`
- Kubernetes Secret for the PostgreSQL password
- webhook destination reachable from the cluster

## PostgreSQL password secret

Default chart values expect:

```yaml
postgres:
  existingSecret:
    name: postgres-secrets
    key: password
```

Create a development secret:

```bash
kubectl create secret generic postgres-secrets \
  --from-literal=password=postgres
```

## Image settings

Default values:

```yaml
image:
  repository: ghcr.io/kanutocd/mammoth
  tag: "0.1.0"
  pullPolicy: IfNotPresent
```

For local Kind testing with a locally built image:

```bash
kind load docker-image live_postgres_webhook-mammoth:latest --name mammoth
```

Install or upgrade with:

```bash
helm upgrade --install mammoth charts/mammoth \
  --set image.repository=live_postgres_webhook-mammoth \
  --set image.tag=latest \
  --set image.pullPolicy=IfNotPresent
```

## PostgreSQL service example

For local Kind testing, you can run PostgreSQL inside Kubernetes and expose it with a service named `postgres-service`.

Example Mammoth override:

```bash
helm upgrade --install mammoth charts/mammoth \
  --set postgres.host=postgres-service \
  --set postgres.port=5432 \
  --set postgres.database=mammoth_demo \
  --set postgres.username=postgres
```

## Webhook URL

The webhook URL must be reachable from inside Kubernetes.

This will not work unless the cluster can reach the public host:

```yaml
webhook:
  url: https://yourservice.com/webhooks/postgres
```

For an in-cluster receiver, use a Kubernetes Service DNS name:

```yaml
webhook:
  url: http://webhook-receiver:9292/webhook
```

## Persistence

The chart mounts a PVC for Mammoth's SQLite database. SQLite is Mammoth's operational memory for checkpoints, dead letters, and replay metadata.

Default storage:

```yaml
persistence:
  storage: "1Gi"
```

## Replica count and replication slots

Run one active Mammoth replica per logical replication slot.

PostgreSQL logical replication slots are consumed by one active subscriber at a time, so the chart uses a single replica by default.

## Useful commands

```bash
kubectl get pods
kubectl get pvc
kubectl logs deploy/mammoth
kubectl describe pod -l app.kubernetes.io/name=mammoth
helm get values mammoth --all
helm get manifest mammoth
```
