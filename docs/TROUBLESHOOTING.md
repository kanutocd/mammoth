# Troubleshooting

This guide records common issues encountered while running Mammoth locally, with Docker Compose, or with Kubernetes.

## `secret "postgres-secrets" not found`

Symptom:

```text
CreateContainerConfigError
Error: secret "postgres-secrets" not found
```

Cause:

The Helm chart references a PostgreSQL password Secret that does not exist.

Fix:

```bash
kubectl create secret generic postgres-secrets \
  --from-literal=password=postgres

kubectl rollout restart deploy/mammoth
```

If your chart values use a different secret name or key, inspect:

```bash
helm get values mammoth --all
helm get manifest mammoth | grep -A5 -B5 postgres-secrets
```

## `could not translate host name "postgres-service.internal"`

Symptom:

```text
PostgreSQL CDC source failed: could not translate host name "postgres-service.internal" to address: Name or service not known
```

Cause:

The default Postgres host is not resolvable inside your Kubernetes cluster.

Fix:

Point Mammoth to a real Kubernetes Service:

```bash
helm upgrade mammoth ./charts/mammoth \
  --set postgres.host=postgres-service \
  --set postgres.port=5432
```

## Mammoth pod is running but no webhook arrives

Possible causes:

- no publication exists
- the table is not part of the publication
- webhook URL is not reachable from inside the cluster
- Mammoth started before the publication was created and needs a restart
- destination returns an error and the event is dead-lettered

Check publications:

```bash
kubectl exec deploy/postgres -- psql -U postgres -d mammoth_demo -c "SELECT * FROM pg_publication;"
```

Create a table and publication:

```bash
kubectl exec deploy/postgres -- psql -U postgres -d mammoth_demo -c \
"CREATE TABLE IF NOT EXISTS orders (id bigserial PRIMARY KEY, status text NOT NULL, total_cents integer NOT NULL);"

kubectl exec deploy/postgres -- psql -U postgres -d mammoth_demo -c \
"CREATE PUBLICATION mammoth_publication FOR TABLE orders;"
```

Restart Mammoth and insert a row:

```bash
kubectl rollout restart deploy/mammoth
kubectl exec deploy/postgres -- psql -U postgres -d mammoth_demo -c \
"INSERT INTO orders (status, total_cents) VALUES ('created', 8888);"
```

## Replication slot is active but nothing is delivered

Check slot movement:

```sql
SELECT
  slot_name,
  active,
  restart_lsn,
  confirmed_flush_lsn
FROM pg_replication_slots;
```

If `confirmed_flush_lsn` moves, Mammoth is consuming the stream. The issue is likely downstream delivery configuration.

Check webhook URL and Mammoth logs:

```bash
kubectl logs deploy/mammoth --tail=200
helm get values mammoth --all
```

## Docker Compose example shows duplicate dead-letter rows

Cause:

The Docker volume was reused across multiple runs with the same sample `event_id`.

Fix:

Reset the example volume:

```bash
docker compose down -v
```

Then rerun the example.

## `sqlite3` is not available in the container

The runtime image may not include `sqlite3`. Keep the runtime image lean and inspect the database with a temporary helper container.

Example:

```bash
docker run --rm -it \
  -v failing_webhook_retry_mammoth_retry_data:/data \
  alpine:3.20 \
  sh -c "apk add --no-cache sqlite && sqlite3 /data/mammoth.db '.tables'"
```

## zsh asks to correct `exec` to `exe`

When running commands like:

```bash
kubectl exec deploy/postgres -- psql -U postgres -d mammoth_demo -c "SELECT 1;"
```

zsh may ask:

```text
zsh: correct 'exec' to 'exe' [nyae]?
```

Answer `n` or disable correction for the command. The `kubectl exec` command is correct.
