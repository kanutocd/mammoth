# Changelog

## 0.1.0 - Unreleased

### Added

* Renamed product and gem from Echo to Mammoth.
* Positioned Mammoth OSS as the reliable PostgreSQL change-event delivery appliance.
* Added PostgreSQL CDC ingestion using:

  * pgoutput-client
  * pgoutput-parser
  * pgoutput-decoder
  * pgoutput-source-adapter
  * cdc-core
* Added PostgreSQL source implementation that realizes the CDC ecosystem contracts.
* Added CDC-core `ChangeEvent` serialization for webhook delivery.
* Added CDC-core `TransactionEnvelope` flattening before sink delivery.
* Added durable SQLite operational state storage.
* Added checkpoint persistence.
* Added dead-letter persistence.
* Added webhook delivery worker with retry support.
* Added operational status reporting.
* Added `mammoth start CONFIG` CLI command.
* Added `mammoth status CONFIG` CLI command.
* Added JSON Schema configuration validation.
* Added public Helm chart under `charts/mammoth`.
* Added multi-stage container image build.
* Added non-root container runtime support.
* Added GitHub Pages documentation workflow.
* Added release workflow for RubyGems publishing.
* Added end-to-end test task using real HTTP, SQLite, and filesystem paths.
* Added RBS signatures and Steep validation.
* Added YARD documentation generation and coverage validation.

### Changed

* Replaced singular replication configuration:

  ```
  replication:
    publication: ...
  ```

  with:

  ```
  replication:
    publications:
      - ...
  ```

  to align with PostgreSQL logical replication and pgoutput-client semantics.

* Hardened Mammoth boundaries to compose CDC ecosystem libraries rather than reimplementing their responsibilities.

* Refactored PostgreSQL CDC source integration around CDC ecosystem contracts.

* Improved Docker image structure and operational examples.

* Expanded example coverage for:

  * PostgreSQL → Webhook
  * Live PostgreSQL replication
  * Failing webhook retry handling
  * Operational state inspection

### Fixed

* Fixed CDC ecosystem RBS integration issues.
* Fixed Steep compatibility with upstream CDC ecosystem gems.
* Fixed Docker entrypoint and runtime configuration handling.
* Fixed live PostgreSQL example startup and operational flow.
* Improved unit and branch test coverage.

