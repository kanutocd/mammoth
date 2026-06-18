# Kubernetes and Helm

Mammoth ships with a Helm chart stored in the repository:

```text
charts/mammoth
```

## Current Distribution Model

The Helm chart is currently distributed through the Mammoth Git repository.

A dedicated Helm repository is not yet published.

Clone the repository:

```bash
git clone https://github.com/kanutocd/mammoth.git
cd mammoth
```

## Render Manifests

```bash
helm template mammoth ./charts/mammoth \
  --set image.repository=ghcr.io/kanutocd/mammoth \
  --set image.tag=latest
```

## Install

```bash
helm install mammoth ./charts/mammoth \
  --set image.repository=ghcr.io/kanutocd/mammoth \
  --set image.tag=latest
```

## Upgrade

```bash
helm upgrade mammoth ./charts/mammoth \
  --set image.repository=ghcr.io/kanutocd/mammoth \
  --set image.tag=latest
```

## Uninstall

```bash
helm uninstall mammoth
```

## Required External Resources

The chart deploys Mammoth. It does not create your full CDC environment.

You must provide:

* PostgreSQL reachable from the cluster
* PostgreSQL logical replication settings
* publication
* replication slot or `auto_create_slot: true`
* Kubernetes Secret for the PostgreSQL password
* webhook destination reachable from the cluster

## PostgreSQL Password Secret

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

## Image Settings

Default values:

```yaml
image:
  repository: ghcr.io/kanutocd/mammoth
  tag: "0.1.1"
  pullPolicy: IfNotPresent
```

Override image settings:

```bash
helm upgrade --install mammoth ./charts/mammoth \
  --set image.repository=ghcr.io/kanutocd/mammoth \
  --set image.tag=latest
```

## Kind Local Development

For local Kind testing with a locally built image:

```bash
kind load docker-image live_postgres_webhook-mammoth:latest --name mammoth
```

Install or upgrade with:

```bash
helm upgrade --install mammoth ./charts/mammoth \
  --set image.repository=live_postgres_webhook-mammoth \
  --set image.tag=latest \
  --set image.pullPolicy=IfNotPresent
```

## PostgreSQL Service Example

For local Kind testing, you can run PostgreSQL inside Kubernetes and expose it with a Service named `postgres-service`.

Example Mammoth override:

```bash
helm upgrade --install mammoth ./charts/mammoth \
  --set postgres.host=postgres-service \
  --set postgres.port=5432 \
  --set postgres.database=mammoth_demo \
  --set postgres.username=postgres
```

## Webhook URL

The webhook URL must be reachable from inside Kubernetes.

This example will only work if the cluster can reach the public host:

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

The chart mounts a PVC for Mammoth's SQLite database.

SQLite is Mammoth's operational memory for:

* checkpoints
* dead letters
* replay metadata

Default storage:

```yaml
persistence:
  storage: "1Gi"
```

Inspect PVCs:

```bash
kubectl get pvc
```

## Replica Count and Replication Slots

Run one active Mammoth replica per logical replication slot.

PostgreSQL logical replication slots are consumed by one active subscriber at a time, so the chart uses a single replica by default.

```yaml
replicaCount: 1
```

## Useful Commands

Inspect deployment status:

```bash
kubectl get pods
kubectl get pvc
kubectl logs deploy/mammoth
kubectl describe pod -l app.kubernetes.io/name=mammoth
```

Inspect Helm values and manifests:

```bash
helm get values mammoth --all
helm get manifest mammoth
```

Restart Mammoth:

```bash
kubectl rollout restart deploy/mammoth
```

## Troubleshooting

See:

* [Troubleshooting](file.TROUBLESHOOTING.html)

Common topics include:

* Helm installation issues
* Kubernetes Secret configuration
* PostgreSQL connectivity
* Publications and replication slots
* Webhook delivery troubleshooting
* SQLite operational state inspection
