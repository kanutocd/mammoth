# Mammoth ecosystem

Mammoth is an ecosystem of cooperating components. This repository contains
the open-source Mammoth Data Plane: the runtime that consumes PostgreSQL change
events and delivers prepared payloads to configured destinations.

```text
Mammoth
├── Mammoth Data Plane
├── Mammoth Control Plane
├── Mammoth Control Agent
└── Mammoth Extensions
```

## Components

| Component | Responsibility | Public status |
| --- | --- | --- |
| Mammoth Data Plane | PostgreSQL CDC consumption, delivery, retries, payload policies, operational state, and destination fanout. | Implemented here; open source under the repository license. |
| Mammoth Control Plane | Multi-tenant inventory, identity and access control, durable orchestration, audit evidence, and operator workflows. | Implemented privately in active 0.40 development; not publicly released. |
| Mammoth Control Agent | Secure node-side enrollment, control-plane communication, command execution, and local reconciliation. | Secure-channel foundation implemented privately; broader managed-node workflows remain planned. |
| Mammoth Extensions | Replaceable destination, runtime, state, and integration adapters. | Data Plane registries are implemented here; additional private and public extensions are planned independently. |

## Boundaries

The Data Plane owns delivery-runtime behavior and local operational state. The
Control Plane governs intent, tenancy, authorization, audit, and orchestration.
The Control Agent connects a managed node to that control boundary and executes
approved work locally. Extensions provide replaceable integration points; they
do not change the Data Plane's core CDC vocabulary.

The Control Plane, Control Agent, and private Extensions are not dependencies
of the open-source Data Plane distribution. The Data Plane remains useful and
operable on its own with its documented configuration and CLI interfaces.

## Public roadmap

The following is a directional view of ecosystem work. “Implemented” refers to
capabilities represented by this repository's public contracts; “planned” does
not promise a release date or availability in this repository.

| Area | Status | Public scope |
| --- | --- | --- |
| Data Plane delivery, retries, dead letters, replay, payload policies, and operational recovery | Implemented | See the versioned README and documentation under `docs/`. |
| Control Plane production persistence, tenant isolation, RBAC, API/UI workflows, auditability, and import tooling | Implemented privately / continuing | Private companion component; remaining workflow normalization and production acceptance work is not a Data Plane release commitment. |
| Control Agent secure enrollment, agent-initiated transport, command journal, and local reconciliation | Partially implemented privately / continuing | Private companion component; public integration contracts will be documented when released. |
| Extension ecosystem beyond the Data Plane's built-in registries | Planned | Additional adapters may be published independently with their own compatibility and license terms. |

For current Data Plane implementation status, use the repository's release
notes, compatibility guide, and public documentation. Private companion
component plans may change independently and should not be treated as a
promise of inclusion in a Data Plane release.

## Licensing and availability

This repository's license applies to the code distributed here. The Control
Plane, Control Agent, and private Extensions are separate works and may have
different availability, licensing, and support terms. Do not assume that a
component described in this overview is downloadable, open source, or included
with the Data Plane unless its own public release documentation says so.
