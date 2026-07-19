<!--
# @title Kubernetes and Helm
-->

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
* replication slot or `auto_create_slot: true` for first-time bootstrap without
  an existing Mammoth checkpoint
* Kubernetes Secret for the PostgreSQL password
* webhook destination reachable from the cluster

For production, manage publications and permanent replication slots as database
infrastructure and set `replication.auto_create_slot: false` after bootstrap.
Do not couple a retained Mammoth PVC to an automatically replaced PostgreSQL
slot: the SQLite checkpoint and the slot's retained WAL describe one continuity
history and must be recovered or reset together.

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
  tag: "1.4.0"
  pullPolicy: IfNotPresent
```

Override image settings:

```bash
helm upgrade --install mammoth ./charts/mammoth \
  --set image.repository=ghcr.io/kanutocd/mammoth \
  --set image.tag=1.4.0
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

## Node Identity

The chart can render optional Mammoth node identity fields for status output and
future control-plane agents:

```yaml
node:
  node_id: mammoth-prod-1
  node_name: mammoth-prod-a
  fleet_id: payments-prod
  environment: production
  labels:
    region: ap-southeast-1
```

## Operational State Adapter

Mammoth OSS uses the SQLite operational state adapter by default:

```yaml
operational_state:
  adapter: sqlite
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

The chart renders webhook headers and signing settings:

```yaml
webhook:
  headers:
    X-Mammoth-Source: production_mammoth
  header_env:
    Authorization: MAMMOTH_WEBHOOK_AUTHORIZATION
  signing:
    algorithm: hmac_sha256
    secret_env: MAMMOTH_WEBHOOK_SIGNING_SECRET
```

Back env-backed webhook values with a Kubernetes Secret:

```yaml
webhook:
  existingSecret:
    name: webhook-secrets
    keys:
      MAMMOTH_WEBHOOK_AUTHORIZATION: authorization
      MAMMOTH_WEBHOOK_SIGNING_SECRET: signing-secret
```

For fanout, set `destinations`. Each destination can map its own env-backed
headers and signing secret env vars to a Kubernetes Secret:

```yaml
destinations:
  - name: primary_webhook
    type: webhook
    enabled: true
    url: https://example.com/webhooks/postgres
    timeout_seconds: 5
    header_env:
      Authorization: MAMMOTH_PRIMARY_WEBHOOK_AUTHORIZATION
    signing:
      algorithm: hmac_sha256
      secret_env: MAMMOTH_PRIMARY_WEBHOOK_SIGNING_SECRET
    existingSecret:
      name: primary-webhook-secrets
      keys:
        MAMMOTH_PRIMARY_WEBHOOK_AUTHORIZATION: authorization
        MAMMOTH_PRIMARY_WEBHOOK_SIGNING_SECRET: signing-secret
  - name: audit_webhook
    type: webhook
    enabled: true
    url: https://audit.example.com/cdc
    timeout_seconds: 5
    route:
      schemas:
        - public
      tables:
        - orders
      operations:
        - insert
        - update
    retry:
      max_attempts: 3
      schedule_seconds:
        - 1
        - 10
```

The rendered Mammoth config stores only environment variable names. The
Deployment sources those variables from the referenced Kubernetes Secret keys.

## Delivery Runtime

The chart renders Mammoth's transaction delivery and downstream runtime
settings:

```yaml
delivery:
  unit: transaction
  ordering:
    scope: transaction

runtime:
  adapter: concurrent
  concurrency: 1
  batch_size: 1
  preserve_order: true
```

Runtime concurrency affects downstream webhook delivery only. It does not create
extra PostgreSQL replication slots or replication connections.

## Persistence

The chart mounts a PVC for Mammoth's SQLite database.

SQLite is Mammoth's operational memory for:

* checkpoints
* dead letters
* delivered-envelope ledger entries used for duplicate suppression and replay

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

The `Recreate` deployment strategy releases the slot before starting the
replacement pod. Do not change the strategy or replica count without assigning
an independent slot and independent operational-state store to each active
relay.

## PostgreSQL operational guardrails

Monitor retained WAL, slot readiness, PostgreSQL disk capacity, archive health,
and catalog-XID age. Mammoth's `/readyz` and `mammoth_postgres_slot_*` metrics
cover slot state; database and infrastructure tooling must cover storage and
catalog health.

The OSS chart currently starts the relay process only. To expose `/readyz` and
`/metrics`, deploy a separate process with the same ConfigMap, PostgreSQL
Secret, and operational-state PVC:

```bash
mammoth observability /app/config/mammoth.config.yaml
```

That process performs read-only slot and state inspection; it must not run
`mammoth start` or open a second replication connection.

Configure `max_slot_wal_keep_size` and, where supported,
`idle_replication_slot_timeout` according to the environment's recovery budget.
These settings can invalidate an unhealthy slot to protect PostgreSQL. They do
not provide a safe Mammoth resume point; an invalidated slot requires external
backfill or reconciliation.

Coordinate PostgreSQL schema migrations with webhook consumers because DDL is
not replicated. Database upgrades must preserve and verify the existing logical
slot or establish explicitly reconciled new operational state before Mammoth
starts.

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
