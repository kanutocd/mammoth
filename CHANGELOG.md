# Changelog

## 0.1.0 - Unreleased

- Rename product and gem from Echo to Mammoth.
- Position Mammoth OSS as the reliable PostgreSQL change-event delivery appliance.
- Add pgoutput-client / parser / decoder / source-adapter integration boundary.
- Serialize CDC-core `ChangeEvent` shaped work into webhook payloads.
- Flatten CDC-core `TransactionEnvelope` shaped work before sink delivery.
- Add `mammoth start CONFIG` CLI command for live operation.
- Add public Helm chart under `charts/mammoth`.
- Add slim multi-stage Dockerfile for OSS image builds.
- Add e2e test task and script using real HTTP, SQLite, and filesystem paths.
- Switch OSS license metadata to MIT.
