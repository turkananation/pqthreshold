# ADR 004: Post-quantum threshold schemes (v2)

**Status:** Proposed  
**Date:** 2026-08-13  
**Deciders:** pqthreshold maintainers  
**Supersedes:** Partial scope of ADR-001 exclusion list for ML-DSA / SLH-DSA

## Context

The package name **pqthreshold** implies post-quantum threshold cryptography. v1 deliberately shipped **classical organizational roots only** (`SchemeId.frostEd25519V1` → 64-byte Ed25519) while member device keys remain on **pqforge** / **pqcrypto** (ADR-001).

That split is still valid for **daily traffic**, but high-assurance deployments increasingly require **quantum-resistant organizational roots** — threshold ML-DSA (FIPS 204) and, later, hash-based SLH-DSA (FIPS 205) — without reconstructing full secrets on one machine.

Constraints unchanged from ADR-001:

- Pure Dart, zero FFI in `pqthreshold` core
- **pqforge-first** for ML-DSA verify and key material ([ADR-002](002-runtime-dependencies.md))
- Combined signatures must verify through **standard pqforge / pqcrypto paths** (no custom verifiers in applications)
- v1 `SchemeId.frostEd25519V1` and PQTH `ver=0x01` objects remain frozen (ADR-003)

NIST **Multi-Party Threshold Cryptography** (MPTC) and recent constructions (Mithril, TALUS, Shamir-nonce DKG, etc.) show **FIPS 204–compatible threshold ML-DSA** is feasible for small `t`-of-`n` (typically `n ≤ 8` for v2 targets). SLH-DSA threshold remains research-heavy and ships after ML-DSA.

## Decision

Adopt a **multi-`SchemeId` v2 stack**. Each scheme gets its own profile document, wire ordinals, domain separation, and ceremony support matrix. v2 is a **major semver** (`2.0.0`), not an extension of v1 Tier 1 semantics.

### v2 scheme identifiers (wire ordinals)

| Ordinal | `SchemeId` | Primary output | Status target |
| ------- | ---------- | -------------- | ------------- |
| `0x0001` | `frostEd25519V1` | 64-byte Ed25519 (RFC 8032) | **Frozen** (v1 production) |
| `0x0002` | `mlDsa44ThresholdV1` | FIPS 204 ML-DSA-44 signature | v2.0 alpha |
| `0x0003` | `mlDsa65ThresholdV1` | FIPS 204 ML-DSA-65 signature | **v2.0 primary** |
| `0x0004` | `mlDsa87ThresholdV1` | FIPS 204 ML-DSA-87 signature | v2.1 |
| `0x0005` | `slhDsa128fThresholdV1` | FIPS 205 SLH-DSA signature | v2.2+ |
| `0x0006` | `hybridFrostMlDsa65V1` | Ed25519 + ML-DSA-65 (dual credential) | v2.2 |

Ordinals `0x0007`–`0x00FF` reserved. Unknown ordinals → `SerializationError`.

### Reference constructions (implementation targets)

| Scheme | Reference profile | Notes |
| ------ | ----------------- | ----- |
| ML-DSA threshold | [ML_DSA_THRESHOLD_PROFILE.md](../ML_DSA_THRESHOLD_PROFILE.md) | Primary: Mithril-style FIPS 204 output; evaluate TALUS for online round count |
| SLH-DSA threshold | [SLH_DSA_THRESHOLD_PROFILE.md](../SLH_DSA_THRESHOLD_PROFILE.md) | Deferred; hash-tree MPC differs from lattice |
| Hybrid dual-root | [PQ_SCHEMES.md](../PQ_SCHEMES.md) §3 | Linked ceremonies; same `ceremonyId` binding, dual public keys |

**Non-goals for v2.0:** ECDSA-P256 threshold, custom non-NIST PQ schemes, or threshold ML-KEM (KEM threshold is a separate problem).

### Parameter limits (v2 ML-DSA / SLH-DSA)

| Rule | Value | Rationale |
| ---- | ----- | --------- |
| Max `n` | **8** | Aligns with Mithril / NIST MPTC small-set focus; revisit via ADR amendment |
| Min production `t` | **2** | Same as v1 production guidance |
| Max `n` (hybrid) | **255** for Ed25519 leg; **8** for ML-DSA leg | Hybrid uses composite params (see profile) |

### Primitive sourcing

- **Verify** combined ML-DSA signatures: `PqSignaturePrimitives.verify` (pqforge → pqcrypto)
- **Do not** add `pqcrypto` to `pqthreshold/pubspec.yaml`; use pqforge only (ADR-002)
- Lattice threshold **signing** math lives under `lib/src/scheme/ml_dsa/` (new); no ML-DSA threshold in pointycastle/Feldman stack

### Phased delivery

| Milestone | Delivers |
| --------- | -------- |
| **M1** (v2.0-alpha) | ADR-004, profiles, `SchemeId` registry, `SchemeCapabilities`, ML-DSA verify wrapper, params validation |
| **M2** (v2.0-beta) | ML-DSA-65 threshold DKG + C3 (2-of-3, 3-of-5); test vectors; `MlDsaThresholdSigner` |
| **M3** (v2.0) | ML-DSA-44/65 production sign-off; CLI `sign` for ML-DSA schemes; review checklist |
| **M4** (v2.1) | ML-DSA-87; optional SLH-DSA profile freeze |
| **M5** (v2.2) | `hybridFrostMlDsa65V1` dual credential ceremony |

Until **M2**, PQ `SchemeId` values may be used for **params / inspect / documentation** only; calling unfinished ceremony APIs throws `SchemeNotImplemented`.

## Consequences

### Positive

- **pq** prefix is justified by first-class FIPS 204 threshold roots in-plane A
- Verifiers stay on pqforge — same stack as member hybrid keys
- v1 consumers unaffected; frozen ordinals and serializers

### Negative

- Large implementation and review surface (lattice MPC ≠ FROST port)
- Smaller max `n` than Ed25519 v1
- Hybrid scheme doubles ceremony complexity
- Independent review required per profile before production (extend [REVIEW_CHECKLIST.md](../REVIEW_CHECKLIST.md))

## Alternatives considered

| Alternative | Rejected because |
| ----------- | ---------------- |
| Keep PQ only on pqforge (status quo) | Does not qualify organizational threshold as PQ |
| Shamir-split ML-DSA secret key + reconstruct to sign | Centralizes secret; C4-only, not C3 |
| Single `SchemeId` with algorithm byte in params | Breaks v1 PQTH simplicity; prefer explicit ordinals |
| Wait for NIST standardization only | MPTC candidates are mature enough for profile + alpha |

## References

- [NIST IR 8214C](https://csrc.nist.gov/projects/threshold-cryptography) — Threshold Cryptography project
- Mithril, TALUS, Shamir-nonce DKG (NIST MPTC / ePrint 2025–2026)
- [FIPS 204](https://csrc.nist.gov/pubs/fips/204/final) — ML-DSA
- [FIPS 205](https://csrc.nist.gov/pubs/fips/205/final) — SLH-DSA
- ADR-001, [SCHEMES.md](../SCHEMES.md), [PQ_SCHEMES.md](../PQ_SCHEMES.md)
