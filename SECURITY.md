<!--
# @title Security Policy
-->

# Security Policy

Mammoth is infrastructure software that processes PostgreSQL change streams and delivers database events to downstream systems.

Security reports are taken seriously. Responsible disclosure helps protect Mammoth users and the systems that depend on it.

---

## Supported Versions

Security fixes are provided for the latest supported Mammoth release line.

| Version                         |         Supported |
| ------------------------------- | ----------------: |
| Latest stable release           |               Yes |
| Older stable releases           |       Best effort |
| Unreleased development branches | No formal support |

Users should upgrade to the latest stable Mammoth release before reporting a suspected vulnerability unless the issue prevents upgrading.

The PostgreSQL compatibility policy is separate from the Mammoth security-support policy. Mammoth currently supports PostgreSQL 14 through PostgreSQL 18 inclusive.

---

## Reporting a Vulnerability

Do not report suspected security vulnerabilities through public GitHub Issues, Discussions, pull requests, or social media.

Use GitHub Private Vulnerability Reporting for the Mammoth repository:

1. Open the Mammoth repository on GitHub.
2. Select **Security**.
3. Select **Advisories**.
4. Select **Report a vulnerability**.
5. Provide the requested details.

Repository:

`https://github.com/kanutocd/mammoth`

When private vulnerability reporting is unavailable, contact the maintainer privately using a verified contact method listed on the maintainer's GitHub profile.

Do not include credentials, production data, access tokens, webhook secrets, database passwords, or other sensitive information that is not necessary to reproduce the issue.

---

## What to Include

A useful report should include:

* A clear description of the vulnerability
* The affected Mammoth version
* The affected component or interface
* The PostgreSQL version, when relevant
* The Ruby version
* The deployment method
* Required configuration or preconditions
* Reproduction steps
* Proof-of-concept code, when safe to provide
* The expected security boundary
* The observed behavior
* Potential impact
* Known mitigations or workarounds
* Whether the issue is already being exploited or publicly discussed

Reports should distinguish between confirmed behavior and suspected impact.

A minimal, controlled reproduction is preferred over logs or data collected from a production environment.

---

## Relevant Security Areas

Security reports may concern any part of Mammoth, including:

* PostgreSQL connection handling
* Logical replication credentials
* Replication-slot management
* Publication access
* Configuration parsing
* Secret handling
* Environment-variable handling
* Webhook authentication
* Destination authorization
* TLS validation
* Payload integrity
* Event confidentiality
* Replay authorization
* Dead-letter handling
* Operational-state storage
* File permissions
* CLI behavior
* Container images
* Helm deployment defaults
* Dependency vulnerabilities
* Denial-of-service conditions
* Resource exhaustion
* Log disclosure
* Injection vulnerabilities
* Unsafe deserialization
* Path traversal
* Command execution
* Privilege escalation
* Cross-tenant data exposure
* Checkpoint manipulation
* Event tampering

This list is not exhaustive.

---

## Response Process

After receiving a report, the maintainer will attempt to:

1. Acknowledge the report.
2. Determine whether the reported behavior is reproducible.
3. Assess severity and affected versions.
4. Identify mitigations.
5. Develop and validate a fix.
6. Prepare a coordinated release.
7. Publish an advisory when appropriate.

Response and remediation times depend on the issue's severity, reproducibility, affected surface, and the maintainer's availability.

No fixed remediation deadline is guaranteed.

---

## Coordinated Disclosure

Reporters are asked to keep vulnerability details private until:

* A fix or mitigation is available
* Affected users have had a reasonable opportunity to upgrade
* A coordinated disclosure date has been agreed upon

Do not publish proof-of-concept exploits, detailed attack instructions, or affected deployment information before coordinated disclosure.

The maintainer may publish a GitHub Security Advisory containing:

* Affected versions
* Severity
* Impact
* Remediation
* Upgrade guidance
* Workarounds
* Credit to the reporter, when requested

---

## Security Fixes

Security fixes may include:

* A patch release
* A minor release
* Configuration guidance
* Deployment hardening
* Dependency updates
* Documentation changes
* Temporary mitigations

Users should apply security releases promptly and review the accompanying advisory before deployment.

Security-related releases may intentionally omit complete exploit details until sufficient time has passed for users to upgrade.

---

## Severity Assessment

Mammoth may use the Common Vulnerability Scoring System (CVSS) as one input when assessing severity.

Additional factors may include:

* Required access level
* Deployment exposure
* Exploit complexity
* Data confidentiality impact
* Data-integrity impact
* Availability impact
* Cross-tenant impact
* Credential exposure
* Ability to alter delivery or checkpoint state
* Ability to suppress, duplicate, or forge events
* Likelihood of exploitation
* Availability of mitigations

A dependency advisory does not automatically mean Mammoth is exploitable. The affected dependency path and actual runtime exposure must be evaluated.

---

## Security Boundaries

Mammoth assumes that operators protect the environments in which it runs.

Mammoth does not provide a security boundary against an attacker who already has unrestricted access to:

* The Mammoth process
* The host operating system
* The container runtime
* The Kubernetes namespace
* The operational-state database
* The PostgreSQL superuser account
* Mammoth configuration files
* Mammoth environment variables
* Downstream destination credentials

Operators remain responsible for host security, network policy, access control, secret management, database permissions, and destination authorization.

---

## Secrets and Credentials

Mammoth configuration may reference sensitive values such as:

* PostgreSQL credentials
* Replication credentials
* Webhook secrets
* Authentication headers
* TLS private keys
* Destination access tokens

Operators should:

* Use a dedicated PostgreSQL role with the minimum required privileges.
* Store secrets outside source control.
* Use secret-management facilities provided by the deployment platform.
* Restrict access to configuration files and environment variables.
* Rotate credentials after suspected exposure.
* Avoid placing secrets directly in command-line arguments.
* Prevent secrets from appearing in logs, crash reports, or CI output.
* Use separate credentials across environments.

Example configuration must use placeholder values rather than usable credentials.

---

## PostgreSQL Privileges

Mammoth should connect using a dedicated PostgreSQL role.

Grant only the privileges required for the intended deployment, such as:

* Database connection
* Logical replication
* Access to the required publications and tables
* Replication-slot access where applicable

Avoid running Mammoth with a PostgreSQL superuser account unless the deployment explicitly requires it and the associated risk is understood.

Operators should review PostgreSQL privileges after configuration changes and upgrades.

---

## Network Security

Production deployments should:

* Use encrypted PostgreSQL connections.
* Validate PostgreSQL server certificates where supported.
* Use HTTPS for webhook and HTTP destinations.
* Validate destination certificates.
* Restrict inbound and outbound network access.
* Avoid exposing operational or administrative endpoints publicly.
* Apply firewall, security-group, or Kubernetes network-policy controls.
* Limit destination access to explicitly approved endpoints.

Disabling TLS validation is not recommended for production environments.

---

## Webhook Security

Webhook destinations should authenticate Mammoth requests and validate their integrity.

Depending on the deployment, operators should consider:

* HTTPS
* Shared-secret authentication
* HMAC signatures
* Timestamp validation
* Replay protection
* Source allowlisting
* Idempotency keys
* Request-size limits
* Rate limits

Downstream systems should treat all event payloads as untrusted input and validate them before use.

A successful network connection alone must not be treated as proof that the destination is authorized.

---

## Event and Payload Security

Change-event payloads may contain sensitive database information.

Operators should:

* Replicate only the tables and columns required by the use case.
* Avoid delivering secrets or regulated data unnecessarily.
* Protect event payloads in transit.
* Restrict access to logs and dead-letter storage.
* Define appropriate retention policies.
* Sanitize payloads before forwarding them to lower-trust systems.
* Review transformations and filters for accidental data leakage.

Mammoth does not automatically classify or redact sensitive application data.

---

## Operational State

Mammoth operational state may contain:

* Checkpoints
* Delivery metadata
* Retry information
* Replay metadata
* Dead-letter entries
* Destination responses
* Error details

Operational-state storage should be protected with appropriate file permissions, access controls, backups, and retention policies.

Operators should assume that operational metadata may reveal information about source tables, delivery behavior, event timing, and downstream systems.

---

## Replay and Redelivery

Replay and redelivery are security-sensitive operations because they can cause historical events to be delivered again.

Administrative workflows should:

* Restrict replay authorization.
* Record who initiated a replay.
* Define the replay range explicitly.
* Prevent accidental delivery to production destinations.
* Preserve audit information.
* Consider duplicate side effects.
* Validate tenant and destination scope.

Downstream systems should implement idempotent processing where practical.

---

## Logging

Logs should support operational diagnosis without exposing sensitive information.

Contributors and operators should avoid logging:

* Passwords
* Access tokens
* Authentication headers
* Private keys
* Connection strings containing credentials
* Full sensitive payloads
* Unredacted destination responses
* Personally identifiable information without a clear need

Debug logging may expose additional details and should be enabled cautiously in production.

---

## Dependency Security

Mammoth depends on third-party Ruby libraries and system components.

Contributors and maintainers should:

* Keep dependencies reasonably current.
* Review security advisories.
* Avoid unnecessary dependencies.
* Pin or constrain dependency versions appropriately.
* Validate dependency updates through tests and CI.
* Avoid executing untrusted package-installation scripts.
* Review transitive dependencies for security-sensitive functionality.

Dependency scanners are useful signals but do not replace manual impact analysis.

---

## Container and Kubernetes Security

For containerized deployments:

* Use trusted Mammoth images.
* Pin production deployments to explicit versions or immutable digests.
* Avoid running containers as root where practical.
* Use read-only filesystems where compatible.
* Mount writable storage only where required.
* Apply CPU and memory limits.
* Restrict Linux capabilities.
* Avoid privileged containers.
* Protect Kubernetes Secrets.
* Apply namespace and network isolation.
* Review Helm values before production use.

The `latest` image tag is convenient for evaluation but should not be used as the sole version constraint in production.

---

## Denial of Service and Resource Exhaustion

Reports involving resource exhaustion are in scope when an attacker or untrusted input can cause disproportionate:

* Memory growth
* CPU consumption
* Disk consumption
* Connection exhaustion
* Retry amplification
* WAL retention
* Queue growth
* Dead-letter growth
* Log volume
* Destination traffic

Ordinary capacity limits under expected workloads are generally operational concerns rather than vulnerabilities.

A report should explain the security boundary crossed and why the resource usage is attacker-controlled or unexpectedly disproportionate.

---

## Out-of-Scope Reports

The following are generally not treated as security vulnerabilities unless they demonstrate a concrete security impact:

* Missing features
* General performance tuning
* Expected duplicate delivery under documented at-least-once semantics
* Unsupported PostgreSQL versions
* Unsupported Ruby versions
* Vulnerabilities requiring unrestricted host or process access
* Reports based only on automated scanner output
* Dependency advisories with no reachable vulnerable path
* Missing security headers on non-browser administrative endpoints
* Self-inflicted misconfiguration
* Publicly documented operational limitations
* Rate-limit concerns without a demonstrated security boundary
* Social engineering
* Physical attacks
* Attacks against third-party systems outside Mammoth's control

Reports containing a credible exploit path will still be reviewed, even when they resemble an item above.

---

## Security Research Guidelines

Good-faith security research should:

* Avoid accessing data that does not belong to the researcher.
* Avoid modifying or deleting user data.
* Avoid disrupting production systems.
* Avoid degrading service availability.
* Use local or isolated test environments.
* Stop testing after confirming the vulnerability.
* Report findings promptly.
* Keep findings confidential during remediation.

This policy does not authorize testing against systems operated by Mammoth users or third parties.

---

## Safe Harbor

The project intends to treat good-faith research conducted under this policy as authorized for the limited purpose of identifying and reporting security vulnerabilities.

This statement does not waive the rights of third parties and does not authorize activity against infrastructure, data, or accounts that the researcher does not own or have explicit permission to test.

Researchers remain responsible for complying with applicable law.

---

## Security Documentation Changes

Security-related documentation changes are welcome through normal pull requests when they do not disclose an unpatched vulnerability.

Changes involving new security-sensitive concepts should also review:

* `CONTRIBUTING.md`
* `docs/GLOSSARY.md`
* `docs/CONFIGURATION.md`
* `docs/POSTGRESQL.md`
* `CHANGELOG.md`

Canonical security and operational terminology should remain consistent with `docs/GLOSSARY.md`.

---

## Attribution

Mammoth may credit vulnerability reporters in the security advisory and release notes.

Reporters may request:

* Public attribution
* Attribution under a preferred name
* Anonymous acknowledgement
* No acknowledgement

Mammoth currently does not operate a paid bug-bounty program.

---

## License

This security policy is part of the Mammoth project documentation and is distributed under the project's MIT License.
