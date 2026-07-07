# Mammoth Diagrams

Mammoth architecture diagrams should communicate operational flow clearly.

## Primary Diagram

![Mammoth Data Plane](assets/diagrams/mammoth-data-plane.svg)

## Diagram Language

- White cards on light gray backgrounds
- PostgreSQL Blue arrows
- Short labels
- No decorative 3D effects
- No generic clip art

## Canonical Flow

PostgreSQL logical replication flows into Mammoth. Mammoth owns delivery correctness, replay, checkpointing, routing, fan-out, delivery ledger, and operational state. Downstream systems are destinations, not Mammoth's source of truth.
