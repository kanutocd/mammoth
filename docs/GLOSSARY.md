<!--
# @title Glossary
-->

# Glossary

This glossary defines the canonical terminology used throughout the Mammoth documentation.

> **Normative terminology:** This glossary is the authoritative source for Mammoth terminology. Public documentation, configuration guides, examples, CLI output, APIs, and contributor documentation should use these definitions consistently. When introducing a new public concept, update this glossary as part of the same change.


Where possible, terminology follows PostgreSQL's official documentation. Terms specific to Mammoth are explicitly identified.

---

## Version Compatibility

Unless otherwise stated throughout the documentation:

- Mammoth supports PostgreSQL 14 through PostgreSQL 18 inclusive.
- "PostgreSQL" refers to logical replication using the `pgoutput` output plugin.
- Version-specific PostgreSQL features are explicitly documented where applicable.

---

# A

## Acknowledgement

Confirmation that a downstream delivery has completed successfully.

Successful acknowledgements allow Mammoth to advance checkpoints and avoid redelivery.

---

## Adapter

A pluggable implementation that integrates Mammoth with an external system.

Examples include:

- Webhook destinations
- PostgreSQL sources
- Future Kafka destinations
- Future S3 destinations

---

## At-Least-Once Delivery

A delivery guarantee in which each event is delivered one or more times.

Under failure conditions, retries or replay may result in duplicate deliveries. Systems that rely on at-least-once delivery are therefore typically designed to process events idempotently.

---

# C

## Change Data Capture (CDC)

A software design pattern for observing and processing changes made to a data source as a stream of change events rather than repeatedly querying or scanning the source for differences.

Change Data Capture is commonly used to synchronize systems, build event-driven architectures, maintain caches and search indexes, replicate data, and trigger downstream processing.

Mammoth implements Change Data Capture using PostgreSQL logical replication.

---

## Change Event

A canonical representation of a database modification.

Examples include:

- INSERT
- UPDATE
- DELETE
- TRUNCATE (future)

Internally Mammoth represents these using `CDC::Core::ChangeEvent`.

---

## Checkpoint

A durable record representing the progress of event processing.

In Mammoth, checkpoints record the highest durably acknowledged PostgreSQL WAL position, allowing processing to resume after interruptions without reprocessing already acknowledged changes.

---

## Commit

The successful completion of a PostgreSQL transaction.

Mammoth only emits committed changes.

Rolled-back transactions are never delivered.

---

# D

## Data Plane

The runtime responsible for reading, processing, and delivering change events.

Mammoth OSS is the data plane of the Mammoth Platform.

---

## Dead Letter Queue (DLQ)

Persistent storage for events that could not be delivered successfully after retry policies have been exhausted.

---

## Dead Letter Entry

A single event or transaction stored in the Dead Letter Queue together with metadata describing the delivery failure.

---

## Delivery

The act of sending one or more change events to a downstream destination.

Examples include:

- HTTP Webhooks
- Kafka (future)
- Amazon S3 (future)

A delivery may require multiple delivery attempts before it is acknowledged successfully.

---

## Delivery Attempt

A single attempt to deliver an event or transaction to a destination.

---

## Delivery Result

The outcome of a delivery attempt, such as success, retry, or permanent failure.

---

## Destination

A system that receives change events from Mammoth.

Destinations are implemented through Destination Adapters.

Examples include:

- HTTP services
- Internal applications
- Event brokers
- Object storage

---

# E

## Event

A logical unit representing a change within the source database.

Depending on configuration, an event may represent:

- a single row change
- an entire committed transaction

---

## Fan-out

The process of delivering the same change event to multiple downstream destinations.

---

## Idempotency

The property of safely processing the same event multiple times without changing the final outcome.

---

# L

## Logical Replication

A PostgreSQL feature that streams logical database changes instead of physical storage blocks.

Mammoth uses logical replication via the `pgoutput` plugin.

---

## LSN

Log Sequence Number.

A monotonically increasing position within PostgreSQL's Write Ahead Log (WAL).

LSNs are used for:

- checkpointing
- replay
- ordering
- replication progress

---

# M

## Mammoth

The open-source PostgreSQL Change Data Capture data plane.

Mammoth provides the core runtime responsible for reliably capturing, processing, and delivering PostgreSQL change events while maintaining operational state for production deployments.

Capabilities include, but are not limited to:

- reliable delivery
- retries
- checkpointing
- replay
- observability
- operational state management

---

## Mammoth Platform

The complete product family consisting of:

- Mammoth OSS (Data Plane)
- Mammoth Extensions
- Mammoth Control Agent
- Mammoth Control Plane

---

# O

## Observability

The collection of logs, metrics, health information, and runtime diagnostics used to understand Mammoth's behavior in production.

---

## Operational State

Persistent runtime metadata maintained by Mammoth.

Examples include:

- checkpoints
- retries
- replay metadata
- delivery history
- dead-letter entries

Operational state is independent of user data.

Operational state is persisted through an Operational State Adapter.

---

## Operational State Adapter

A pluggable component responsible for persisting and retrieving Mammoth operational state.

---

## Ordering Guarantee

The documented guarantees Mammoth provides regarding the order in which events and transactions are delivered.

---

# P

## Payload Policy

A configurable policy that determines what information is included in downstream event payloads.

---


## Publication

A PostgreSQL object defining which tables are exposed through logical replication.

Mammoth subscribes to publications.

---

## Processor

A component that receives a change event and performs work.

Examples include:

- filtering
- transformation
- routing
- delivery

---

# R

## Replay

The act of reprocessing previously captured events.

In Mammoth, replay uses durable operational state to safely redeliver historical events for recovery or operational purposes.

---

## Replay Window

The range of checkpoints or WAL positions selected for replay.

---

## Replication Slot

A PostgreSQL object that preserves WAL required by logical replication clients.

Mammoth consumes change events from a logical replication slot.

---

## Retry Policy

The configuration governing how failed deliveries are retried.

---

## Runtime Adapter

A pluggable abstraction that allows Mammoth to execute processors using different runtime implementations.

---

# S

## Sink

A synonym for Destination.

Historically "sink" refers to the endpoint that ultimately consumes events.

---

## Source

The upstream system producing change events.

Today Mammoth officially supports PostgreSQL.

Future releases may support additional sources.

---

# T

## Transaction

A group of one or more SQL statements committed atomically.

Mammoth preserves transaction boundaries when configured for transaction-aware delivery.

---

## Transaction Envelope

A message containing all changes that belong to a single committed PostgreSQL transaction.

This allows downstream systems to process commits atomically.

---

# W

## WAL

Write Ahead Log.

PostgreSQL's durable transaction log used for crash recovery and replication.

Logical replication streams are derived from WAL records.

---

## Webhook

An HTTP endpoint that receives change events from Mammoth.

Webhooks are the primary destination supported by Mammoth OSS.

---

## Webhook Payload

The serialized event or transaction body delivered to an HTTP webhook destination.


