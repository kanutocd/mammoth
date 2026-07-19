<!--
# @title Contributing Guide
-->

# Contributing to Mammoth

Thank you for considering contributing to Mammoth.

Mammoth is an open-source PostgreSQL Change Data Capture (CDC) data plane focused on correctness, reliability, operational clarity, and long-term maintainability. Contributions to code, tests, documentation, examples, tooling, and project discussions are welcome.

This document defines the contribution workflow and engineering standards expected for the project.

---

## Before You Start

Review existing GitHub Issues and Discussions before opening a new issue or beginning substantial work.

For significant features, architectural changes, new public interfaces, or changes to compatibility guarantees, open an issue or discussion first. This allows the proposed direction and scope to be reviewed before implementation begins.

---

## Ways to Contribute

Contributions may include:

* Bug reports and fixes
* Performance improvements
* Documentation corrections and additions
* Examples and operational guides
* Test coverage improvements
* PostgreSQL compatibility validation
* Destination adapters
* Developer tooling
* Continuous integration improvements
* Security and reliability improvements

---

## Development Principles

### Reliability First

Mammoth is infrastructure software. Correctness, recoverability, and predictable behavior take precedence over convenience or marginal performance gains.

Changes should account for:

* Process interruption
* PostgreSQL disconnection
* Destination failure
* Retry and replay behavior
* Duplicate delivery
* Checkpoint consistency
* Partial operational failure

### Small, Focused Changes

Pull requests should address one cohesive concern whenever practical.

Small changes are easier to review, test, document, and safely release.

### Backward Compatibility

Public interfaces should remain backward compatible unless a breaking change is necessary and has been discussed in advance.

Breaking changes must be:

* Explicitly justified
* Documented in `CHANGELOG.md`
* Reflected in migration guidance where applicable
* Released according to the project's versioning policy

### Documentation Is Part of the Feature

A feature is not complete until its relevant documentation has been updated.

Documentation should describe actual behavior rather than intended or speculative behavior.

### Tests Are Required

Every behavioral change should include appropriate automated tests.

Bug fixes should ordinarily include a regression test that fails without the fix.

---

## Development Environment

### Requirements

* Ruby 4.0 or newer
* PostgreSQL 14 through PostgreSQL 18
* Bundler
* Git
* Docker or another suitable container runtime for matrix and end-to-end testing

Clone the repository and install its dependencies:

```bash
git clone https://github.com/kanutocd/mammoth.git
cd mammoth
bundle install
```

Run the standard test suite:

```bash
bundle exec rake test
```

Run PostgreSQL end-to-end tests when the change affects logical replication, replication slots, publications, checkpointing, source processing, or delivery behavior:

```bash
bundle exec rake test:e2e
```

Consult the repository's Rake tasks and CI workflow for the current authoritative validation commands.

---

## Branch Naming

Use short, descriptive branch names.

Examples:

```text
feature/add-destination-adapter
fix/retry-backoff
docs/postgresql-guide
refactor/checkpoint-store
test/slot-recovery
ci/postgresql-matrix
```

Recommended prefixes include:

* `feature/`
* `fix/`
* `docs/`
* `refactor/`
* `test/`
* `ci/`
* `chore/`

---

## Coding Standards

Follow the conventions already established in the codebase.

Contributions should:

* Prefer explicit, readable implementations.
* Avoid unnecessary metaprogramming.
* Keep methods and objects focused on a clear responsibility.
* Avoid introducing dependencies without a concrete benefit.
* Preserve existing public behavior unless a change is intentional.
* Handle failures explicitly.
* Avoid silently discarding errors or source data.
* Add YARD documentation for new or changed public Ruby APIs.
* Update RBS signatures when typed interfaces change.
* Follow the project's configured static-analysis and style checks.

Do not refactor unrelated code as part of a narrowly scoped change unless the refactoring is required to implement the change safely.

---

## Canonical Terminology and the Glossary

`docs/GLOSSARY.md` defines the canonical terminology used by Mammoth.

Contributors should use glossary terms consistently across:

* Source code
* Public APIs
* Configuration
* CLI output
* Log messages
* Documentation
* Examples
* Issue and pull-request descriptions

For example, contributors should not interchange terms such as **destination**, **sink**, **checkpoint**, **replay**, **change event**, and **transaction envelope** unless the glossary explicitly defines the relationship between them.

When introducing a new domain concept or public term:

1. Check whether an existing glossary term already represents the concept.
2. Prefer the established term where it is technically accurate.
3. Add or revise the corresponding entry in `docs/GLOSSARY.md` when a genuinely new concept is introduced.
4. Update related documentation to use the canonical term consistently.

Changes that intentionally rename or redefine an established term should explain the rationale and identify any compatibility or migration implications.

---

## Testing Requirements

Choose tests according to the affected layer.

### Unit Tests

Use unit tests for isolated behavior such as:

* Value objects
* Configuration parsing
* Retry calculations
* Serialization
* Routing
* Validation
* Operational-state transitions

### Integration Tests

Use integration tests where multiple Mammoth components collaborate but a complete PostgreSQL replication environment is not required.

### End-to-End Tests

Use end-to-end tests for behavior involving:

* PostgreSQL logical replication
* Publications
* Replication slots
* WAL positions
* Transaction boundaries
* Checkpoint advancement
* Restart and recovery
* Delivery acknowledgement
* Version-dependent PostgreSQL behavior

Before opening a pull request, run all validation relevant to the change.

At minimum:

```bash
bundle exec rake test
```

For replication-sensitive changes:

```bash
bundle exec rake test:e2e
```

Tests should be deterministic. Avoid arbitrary sleeps where observable state or bounded polling can be used instead.

---

## PostgreSQL Compatibility

Mammoth supports PostgreSQL 14 through PostgreSQL 18 inclusive.

Contributions must preserve compatibility across this supported range unless the proposed change explicitly modifies the support policy.

When using version-dependent PostgreSQL functionality:

* Detect the server version or capability.
* Query only fields available on that PostgreSQL version.
* Provide a safe fallback where appropriate.
* Add tests for relevant version boundaries.
* Document version-specific behavior.

For example, some columns in `pg_replication_slots` are available only in newer PostgreSQL versions and must be inspected conditionally.

`idle_replication_slot_timeout` is a PostgreSQL 18 feature and must not be assumed to exist on PostgreSQL 14 through PostgreSQL 17.

New PostgreSQL major versions are not considered supported until the project's compatibility suite has validated them and the support policy has been updated.

---

## Documentation Requirements

Significant changes should update all applicable documentation.

Relevant files may include:

* `README.md`
* `CHANGELOG.md`
* `docs/README.md`
* `docs/GLOSSARY.md`
* `docs/COMPATIBILITY.md`
* `docs/POSTGRESQL.md`
* Configuration documentation
* CLI documentation
* Architecture documentation
* Operational guides
* Troubleshooting documentation
* Examples

Documentation should include:

* What changed
* Why the behavior exists
* How users configure or invoke it
* Relevant defaults
* Failure behavior
* Compatibility constraints
* Operational consequences

When terminology changes or a new public concept is introduced, update `docs/GLOSSARY.md` as part of the same pull request.

---

## Public Interface Stability

The following are considered public interfaces:

* Documented Ruby APIs
* Configuration keys and values
* Configuration schemas
* CLI commands and options
* Exit statuses
* JSON payload formats
* Webhook payloads
* Destination adapter contracts
* Operational-state contracts
* Documented runtime behavior
* Canonical terminology defined in `docs/GLOSSARY.md`

Changes to public interfaces require careful compatibility analysis.

A pull request affecting a public interface should state whether the change is:

* Backward compatible
* Deprecating existing behavior
* Breaking
* Internal only

Do not characterize an interface as internal when it is documented or relied upon by examples.

---

## Performance and Resource Usage

Mammoth processes database change streams and may run continuously for extended periods.

Contributors should avoid changes that unnecessarily increase:

* Memory retention
* Object allocation
* CPU utilization
* Delivery latency
* Checkpoint latency
* PostgreSQL WAL retention
* Connection usage
* Operational-state growth

Performance-sensitive changes should include benchmarks or before-and-after measurements whenever practical.

A throughput improvement should not weaken delivery guarantees, ordering guarantees, checkpoint correctness, or failure recovery.

---

## Commit Messages

Use concise commit messages that describe the intent of the change.

Conventional Commit prefixes are encouraged:

```text
feat:
fix:
docs:
test:
refactor:
perf:
build:
ci:
chore:
```

Examples:

```text
fix: inspect invalidation_reason only on PostgreSQL 17+
docs: define checkpoint terminology in glossary
test: cover replication-slot inspection on PostgreSQL 14
ci: test logical replication against PostgreSQL 14-18
```

Avoid vague messages such as `update`, `changes`, or `fix tests`.

---

## Pull Requests

A pull request should include:

* A concise explanation of the problem
* The chosen implementation
* Important design trade-offs
* Compatibility implications
* Testing performed
* Documentation changes
* Operational or migration considerations

Keep pull requests focused. Separate unrelated changes unless they are technically inseparable.

### Pull Request Checklist

Before submitting a pull request, verify:

* [ ] The change has a clear and limited scope.
* [ ] Code follows the existing project conventions.
* [ ] Standard tests pass.
* [ ] Relevant end-to-end tests pass.
* [ ] New behavior is covered by tests.
* [ ] PostgreSQL 14–18 compatibility has been considered.
* [ ] Version-specific PostgreSQL behavior is guarded.
* [ ] Documentation has been updated.
* [ ] `docs/GLOSSARY.md` has been reviewed for terminology consistency.
* [ ] New public terminology has been added to the glossary.
* [ ] `CHANGELOG.md` has been updated when applicable.
* [ ] Public APIs have YARD documentation.
* [ ] RBS signatures have been updated when applicable.
* [ ] Backward compatibility has been evaluated.
* [ ] Performance or resource implications have been considered.
* [ ] No unrelated refactoring is included.

---

## Engineering Quality Standard

A complete feature should include all applicable engineering artifacts:

* Implementation
* Automated tests
* Documentation
* Usage examples
* Glossary updates
* YARD documentation
* RBS signatures
* Compatibility handling
* CHANGELOG entry

Not every change requires every artifact. However, omitting an applicable artifact should be deliberate rather than accidental.

---

## Reporting Bugs

Bug reports should include enough information to reproduce and diagnose the problem.

Where applicable, include:

* Mammoth version
* Ruby version
* PostgreSQL version
* Operating system
* Deployment method
* Relevant configuration with secrets removed
* Expected behavior
* Actual behavior
* Logs or stack traces
* Minimal reproduction steps

Do not include credentials, database passwords, webhook secrets, access tokens, or confidential application data.

---

## Reporting Security Issues

Do not disclose suspected security vulnerabilities through public GitHub Issues or Discussions.

Follow the private reporting process documented in `SECURITY.md`.

---

## License

By submitting a contribution, you agree that your contribution will be licensed under the project's MIT License.

---

## Thank You

Thank you for helping improve Mammoth.

Contributions that improve correctness, documentation, compatibility, operational safety, and maintainability directly strengthen the reliability of the Mammoth data plane.
