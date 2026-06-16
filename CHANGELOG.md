# Changelog

## 0.1.0 - Unreleased

### Product & Positioning

- Rename product and gem from Echo to Mammoth.
- Position Mammoth OSS as the reliable PostgreSQL change-event delivery appliance.
- Adopt the tagline: "Reliable delivery of PostgreSQL change events."

### CDC Integration

- Add pgoutput-client / pgoutput-parser / pgoutput-decoder integration boundary.
- Add pgoutput-source-adapter integration boundary.
- Consume normalized CDC::Core primitives rather than raw pgoutput protocol messages.
- Serialize CDC::Core::ChangeEvent shaped work into webhook payloads.
- Flatten CDC::Core::TransactionEnvelope shaped work before sink delivery.

### Runtime & Delivery

- Add webhook delivery sink with retry-aware delivery workflow.
- Add checkpoint persistence using SQLite.
- Add dead-letter and replay metadata persistence primitives.
- Add delivery-state tracking for reliable delivery workflows.

### Configuration

- Add YAML-based configuration.
- Add JSON Schema validation support for Mammoth configuration files.
- Add CLI configuration validation workflow.

### CLI

- Add `mammoth start CONFIG` CLI command for live operation.

### Packaging & Deployment

- Add public Helm chart under `charts/mammoth`.
- Add slim multi-stage Dockerfile for OSS image builds.
- Add container image support for `ghcr.io/kanutocd/mammoth`.

### Testing

- Add end-to-end test suite using real HTTP delivery, SQLite, and filesystem paths.
- Enforce Docker-free unit tests through dependency injection boundaries.
- Improve line and branch test coverage.
- Add coverage reporting and quality gates.

### Type Signatures

- Generate and curate RBS signatures.
- Add Steep type-checking validation.
- Add RBS validation workflow.

### Documentation

- Improve YARD documentation coverage.
- Add documentation quality validation workflow.

### Licensing

- Switch OSS license metadata to MIT.