# Mammoth Composite Replica Identity Demo

This live example proves that Mammoth preserves a composite, non-`id` replica
identity across all row-change operations:

```text
memberships PRIMARY KEY (tenant_id, member_uuid)
      ↓
INSERT + UPDATE + DELETE in one transaction
      ↓
PostgreSQL logical replication
      ↓
catalog-derived ReplicaIdentityResolver mapping
      ↓
one TransactionEnvelope webhook payload
```

The receiver validates that every event has this complete identity:

```json
{"tenant_id":9,"member_uuid":"member-1"}
```

It returns HTTP 422 if an operation is missing a key column or if the expected
`INSERT`, `UPDATE`, `DELETE` sequence is not preserved.

## Run

```bash
docker compose up --build
```

The compose stack starts PostgreSQL 17 with logical replication, a webhook
receiver, Mammoth, and a producer that commits the three row changes together.

## Expected receiver output

```text
payload type: transaction.committed
event_count: 3
event[0]: insert memberships identity={"tenant_id" => 9, "member_uuid" => "member-1"}
event[1]: update memberships identity={"tenant_id" => 9, "member_uuid" => "member-1"}
event[2]: delete memberships identity={"tenant_id" => 9, "member_uuid" => "member-1"}
composite identity verified for INSERT, UPDATE, and DELETE
```

Follow only the receiver logs with:

```bash
docker compose logs -f webhook_receiver
```

## What this demonstrates

Before streaming, Mammoth inspects the publication catalog and obtains the
ordered identity columns for each relation. It passes those mappings to
`Pgoutput::SourceAdapter::ReplicaIdentityResolver`, which owns normalization
into each CDC event's `primary_key`. Mammoth then serializes that value as the
webhook `identity`.

The table intentionally has no column named `id`. The example therefore catches
fallback heuristics, partial composite keys, and loss of the key-only old tuple
that PostgreSQL sends for a `DELETE` under the default primary-key replica
identity.

The example's bootstrap SQL creates the publication because that file owns the
demo database schema. In production, keep publication creation in application
migrations, database bootstrap SQL, or infrastructure tooling rather than in
the pgoutput transport client.

## Clean up

```bash
docker compose down -v
```
