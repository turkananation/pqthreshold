# ADR 001: Scheme selection for v1

**Status:** Accepted  
**Date:** 2026-08-13  
**Deciders:** pqthreshold maintainers

## Context

`pqthreshold` must choose concrete algorithms before implementation. Open decision #1 in `doc/ARCHITECTURE.md` blocked all crypto modules. Constraints:

- Pure Dart, zero FFI
- Combined signatures must verify through ordinary Ed25519 APIs (pqforge / application)
- Minimal new dependencies — pqforge-first; pointycastle only for group ops pqforge lacks
- Post-quantum threshold schemes excluded from v1

## Decision

Adopt for v1:

1. **FROST (Ed25519)** for threshold signing
2. **Feldman VSS** over the Ed25519 scalar field for dealer-based sharing
3. **Gennaro-style DKG** producing FROST-compatible keys for dealer-less root generation

Single scheme identifier: `SchemeId.frostEd25519V1`.

## Consequences

### Positive

- One curve / field stack end-to-end
- Threshold signatures are standard 64-byte Ed25519 — no custom verifier
- Aligns with pqforge hybrid Ed25519 usage
- FROST draft provides structure and vectors

### Negative

- Not post-quantum; application must hybridize at device layer
- C6 (proactive refresh) and C4-B (re-share without reconstruct) deferred to v2
- Pedersen VSS deferred — dealer sees secret during C2 (expected for migration)

## Alternatives considered

| Alternative | Rejected because |
| ----------- | ---------------- |
| ECDSA-P256 threshold | Different stack; pqforge primary path is Ed25519 |
| ML-DSA threshold | Immature; excluded by security scope |
| Custom ad-hoc threshold Ed25519 | Less reviewed than FROST |
| pointycastle for all Ed25519 | Bypasses `PqClassical`; duplicates pqforge verify/sign |
| Direct pointycastle-only dep | Duplicates pqforge; bypasses facades |

## References

- [draft-irtf-cfrg-frost-15](https://datatracker.ietf.org/doc/draft-irtf-cfrg-frost/)
- `doc/SCHEMES.md`
