# v1 Compatibility

Mammoth follows semantic versioning for its supported public contracts. The
v1 promise applies throughout the 1.x release line.

## Configuration

Configuration accepted by Mammoth 1.0 remains valid throughout 1.x unless it is
unsafe or was already rejected by the published JSON Schema.

Minor releases may:

- add optional sections, keys, enum values, adapters, or destinations;
- add validation for combinations that could not operate safely; and
- deprecate a field while continuing to accept it for the remainder of 1.x.

Removing a supported key, changing its type, changing its established meaning,
or making an optional key unconditionally required needs a major release.
Security or data-safety corrections may reject a previously accepted unsafe
combination; such exceptions are documented prominently.

Run `mammoth validate CONFIG` with the target version before every deployment.

## Webhook Payloads

The documented serialized forms of `CDC::Core::ChangeEvent` and
`CDC::Core::TransactionEnvelope` are supported v1 contracts. Within 1.x,
Mammoth does not remove or rename established envelope fields or change their
types and meanings incompatibly.

The canonical field shapes, column-change semantics, and event-ID behavior are
defined in [Webhook Payloads](file.WEBHOOK-PAYLOADS.html).

Minor releases may add fields. Receivers should ignore unknown fields and use
`event_id` or an appropriate domain key for destination-side idempotency.

An opt-in destination payload policy intentionally changes configured row
content by removing or masking selected columns. Policy-free configurations
retain the canonical v1 payload profile. Policy metadata is additive, and a
stored dead letter retains the profile and fingerprint used when it was
prepared.

Columns inside an event's row `data`, identity, or old/new values reflect the
source PostgreSQL schema and replica identity. They are not frozen by Mammoth's
version. Coordinate schema evolution with receivers, as demonstrated by
`examples/schema_evolution`.

## CLI Behavior

Documented command names, required positional arguments, option meanings, exit
success/failure behavior, and operational effects remain compatible throughout
1.x.

Human-readable prose, whitespace, table layout, log messages, and diagnostic
detail may improve in minor releases and are not a machine-readable API.
Automation should prefer exit status, HTTP observability endpoints, persisted
state, and documented structured payloads instead of parsing terminal prose.

Removing a command or option, changing a successful workflow into a different
operation, or incompatibly changing documented exit behavior needs a major
release.

## Operational-State Migrations

Mammoth 1.x preserves forward upgrade paths for operational state created by an
earlier 1.x release. The configured adapter applies versioned migrations
idempotently before using a store.

Migrations preserve checkpoints, pending dead letters, and delivered-envelope
ledger records unless release notes explicitly describe a corrective
reconciliation. A destructive or non-automatic migration requires a major
release and an operator migration guide.

Downgrades are not guaranteed. Back up the operational-state store before an
upgrade, do not run different Mammoth versions against the same SQLite file,
and verify `mammoth status CONFIG` after migration.

## Outside the Promise

The v1 compatibility promise does not turn external or deployment-specific
behavior into a Mammoth contract. In particular:

- PostgreSQL DDL, sequence state, slot retention policy, and disk capacity
  remain externally operated;
- destination business semantics and global idempotency remain destination
  responsibilities;
- human-readable logs and benchmark results may change;
- extension implementations must obey their documented adapter contracts; and
- upstream PostgreSQL behavior remains subject to the supported server version.

Mammoth fails closed when continuity or replica-identity safety cannot be
established rather than preserving compatibility by silently weakening those
guarantees.
