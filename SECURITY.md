# Security Policy

## Supported versions

| Version | Supported |
| ------- | --------- |
| 0.1.x   | Planning / early development — report issues anyway |

## Reporting a vulnerability

**Do not** open a public GitHub issue for security vulnerabilities.

Report privately to the maintainers via GitHub **Security Advisories** on this repository, or contact the repository owner through GitHub's private vulnerability reporting feature.

Include:

- Affected version or commit
- Component (`sharing`, `dkg`, `signing`, etc.) and scheme if known
- Minimal reproduction steps
- Impact assessment (e.g., recovery with fewer than `t` shares, forgery without quorum)

We aim to acknowledge reports within **7 days** and provide a remediation timeline when possible.

## Full security model

The threat model, assumptions, claim boundaries, and operational checklist are in **[doc/SECURITY.md](doc/SECURITY.md)**. Read that document before integrating or deploying threshold roots.

## Scope

In-scope for private reports:

- Cryptographic flaws in `pqthreshold` implementations
- Fail-open behavior (partial secrets or signatures on error)
- Serialization confusion across ceremonies
- Broken threshold invariants in library code

Out of scope:

- Application transport, authentication, or share storage (integrator responsibility)
- Issues in `pqforge` or `pqcrypto` — report to those projects
- Endpoint compromise or quorum collusion within policy

## Disclosure

We follow coordinated disclosure. Please allow time for a fix before public discussion. Credit will be given in CHANGELOG/advisory when reporters wish to be named.
