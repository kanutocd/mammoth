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
| Mammoth Control Plane | Multi-tenant inventory, identity and access control, durable orchestration, audit evidence, and operator workflows. | Implemented privately in active development; not publicly released. |
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
| Multi-source PostgreSQL ingestion | Planned | An optional future Data Plane mode that supervises multiple independent PostgreSQL sources. Each source retains its own replication slot, checkpoint, acknowledgement, retry, replay, health, and operational state while sharing a single Mammoth runtime. Current releases remain intentionally single-source. |

### Multi-source PostgreSQL ingestion

| Status | Planned |
|--------|---------|
| **Capability** | A future Data Plane mode that supervises multiple, independent PostgreSQL logical replication sources within a single Mammoth runtime while preserving complete operational isolation per source. |

The current Mammoth Data Plane is intentionally **single-source**.

**Architectural invariant:** Every PostgreSQL source owns exactly one logical replication slot and one isolated operational state.

The current single-source architecture is a deliberate design choice rather than a technical limitation. It minimizes operational complexity, isolates failure domains, and establishes a consistent ownership model that future multi-source supervision extends without changing.

A single Data Plane instance owns:

- one PostgreSQL source;
- one logical replication slot;
- one logical replication stream;
- one isolated operational state; and
- one independent runtime lifecycle.

This design keeps the runtime operationally simple and predictable.

Future releases may introduce an **optional multi-source mode** that allows a single Data Plane process to supervise multiple PostgreSQL sources. Each source will continue to behave as an independent replication runtime.

The feature is intended for deployments that replicate from multiple independent PostgreSQL databases while reducing deployment and operational overhead. It is not intended to multiplex multiple replication slots from the same PostgreSQL source into a shared processing pipeline.

### Source isolation

Regardless of deployment mode, every source remains isolated.

Each source owns its own:

- PostgreSQL connection;
- logical replication slot;
- publication;
- checkpoint progression;
- acknowledgement lifecycle;
- retry state;
- dead-letter state;
- replay metadata;
- health reporting; and
- operational metrics.

Operational state is isolated on a per-source basis. A checkpoint, retry, acknowledgement, replay, or health transition for one source cannot advance, modify, or invalidate the operational state of another source.

### Runtime model


Conceptually, a future multi-source Data Plane behaves as a supervisor of independent Source Runtimes.

```text
                    Mammoth Data Plane
                          |
               Source Runtime Supervisor
          +---------------+---------------+
          |               |               |
          |               |               |

     Source Runtime   Source Runtime   Source Runtime

          |               |               |

    PostgreSQL A    PostgreSQL B    PostgreSQL C

          |               |               |

        Slot A          Slot B          Slot C
```

The Data Plane coordinates the Source Runtimes but does not merge their replication state.

Each Source Runtime is independently recoverable and progresses its replication stream without coordinating checkpoints or acknowledgements with other Source Runtimes.

### Ordering

Ordering is guaranteed **only within each PostgreSQL source**.

Mammoth will not attempt to establish a global ordering across independent PostgreSQL databases or replication streams.

Ordering guarantees terminate at the source boundary.

### Operational state

The default SQLite operational store remains the authoritative operational state for the Data Plane.

In multi-source mode, it maintains logically isolated state for every source, including:

- checkpoints;
- acknowledgements;
- retries;
- dead letters;
- replay metadata; and
- health information.

The physical storage implementation may evolve over time, but per-source operational isolation remains a core architectural guarantee.

### Compatibility

Multi-source support is intended to be fully opt-in.

Existing single-source deployments, configuration files, operational procedures, and CLI interfaces remain valid without modification.

### Planned implementation sequence

```text
Single-source (today)

Data Plane
     |
Source Runtime
     |
PostgreSQL
     |
Replication Slot
```

```text
Multi-source (future)

Data Plane

├── Source Runtime
│      |
│   PostgreSQL A
│      |
│    Slot A
│
├── Source Runtime
│      |
│   PostgreSQL B
│      |
│    Slot B
│
└── Source Runtime
       |
   PostgreSQL C
       |
     Slot C
```

The intended implementation sequence is:

1. Introduce an optional source collection while preserving full single-source compatibility.
2. Introduce independent Source Runtime supervision.
3. Add per-source checkpointing, acknowledgements, replay, metrics, and health reporting.
4. Validate multi-source operational behavior, including recovery, fencing, failover, and high availability.
5. Declare the feature production-ready after operational certification.

This roadmap is directional and does not imply a specific release or version.

The Data Plane supervises independent Source Runtimes. It does not merge, coordinate, or establish a global ordering across independent PostgreSQL replication streams.

## Licensing and availability

This repository's license applies to the code distributed here. The Control
Plane, Control Agent, and private Extensions are separate works and may have
different availability, licensing, and support terms. Do not assume that a
component described in this overview is downloadable, open source, or included
with the Data Plane unless its own public release documentation says so.
