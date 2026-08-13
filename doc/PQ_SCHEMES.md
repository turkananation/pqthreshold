# PQ_SCHEMES.md

**pqthreshold** — Post-quantum threshold schemes (v2)

Status: formative specification (M1 — registry + profiles)  
Audience: implementers, reviewers  
Prerequisites: [ADR-004](adr/004-pq-threshold-schemes.md), [SCHEMES.md](SCHEMES.md), [PARAMS.md](PARAMS.md)

---

## 1. Purpose

v1 locked a **single classical** organizational root (`frostEd25519V1`). v2 adds **NIST PQ threshold signatures** so Plane A ([INTEGRATION.md](INTEGRATION.md) §3) can issue credentials that verify with **pqforge ML-DSA / SLH-DSA paths**, not only Ed25519.

This document maps **SchemeId → algorithm → ceremonies → verifier**. Cryptographic details live in profile documents:

| Profile | Scheme |
| ------- | ------ |
| [FROST_PROFILE.md](FROST_PROFILE.md) | `frostEd25519V1` |
| [ML_DSA_THRESHOLD_PROFILE.md](ML_DSA_THRESHOLD_PROFILE.md) | `mlDsa*ThresholdV1` |
| [SLH_DSA_THRESHOLD_PROFILE.md](SLH_DSA_THRESHOLD_PROFILE.md) | `slhDsa128fThresholdV1` |

---

## 2. Why ML-DSA threshold is not “FROST with bigger keys”

Ed25519 FROST works because Schnorr linearity lets parties combine nonce commitments and signature shares additively. **ML-DSA (FIPS 204) uses rejection sampling and rounding**; nonce and signature shares do not compose with Shamir/Feldman over a 32-byte field.

v2 ML-DSA threshold therefore requires a **lattice-specific protocol** (see ML-DSA profile). Do not reuse `ThresholdSigner` / FROST wire messages for ML-DSA schemes.

---

## 3. Scheme registry (v2)

| `SchemeId` | Ordinal | Combined signature | Verify via |
| ---------- | ------- | ------------------ | ---------- |
| `frostEd25519V1` | `0x0001` | 64 bytes Ed25519 | `PqClassical.provider.ed25519Verify` |
| `mlDsa44ThresholdV1` | `0x0002` | ML-DSA-44 (2420 B) | `PqSignaturePrimitives.verify(mlDsa44, …)` |
| `mlDsa65ThresholdV1` | `0x0003` | ML-DSA-65 (3309 B) | `PqSignaturePrimitives.verify(mlDsa65, …)` |
| `mlDsa87ThresholdV1` | `0x0004` | ML-DSA-87 (4627 B) | `PqSignaturePrimitives.verify(mlDsa87, …)` |
| `slhDsa128fThresholdV1` | `0x0005` | SLH-DSA-Shake-128f | pqforge SLH-DSA verify (TBD) |
| `hybridFrostMlDsa65V1` | `0x0006` | Ed25519 + ML-DSA-65 | Both verifiers |

### Production readiness (`SchemeCapabilities`)

| Scheme | C1 DKG | C3 sign | M milestone |
| ------ | ------ | ------- | ----------- |
| `frostEd25519V1` | ✅ | ✅ | shipped (v1) |
| `mlDsa44ThresholdV1` | ✅ simulate | ✅ simulate | v2.0-beta (Mithril bridge) |
| `mlDsa65ThresholdV1` | 🔲 M3 | 🔲 M3 | v2.0-beta target |
| `mlDsa87ThresholdV1` | 🔲 M4 | 🔲 M4 | v2.1 |
| `slhDsa128fThresholdV1` | 🔲 M5 | 🔲 M5 | v2.2+ |
| `hybridFrostMlDsa65V1` | 🔲 M5 | 🔲 M5 | v2.2 |

Until a scheme reaches its milestone, APIs throw `SchemeNotImplemented`.

---

## 4. Hybrid dual-root (`hybridFrostMlDsa65V1`)

Transition pattern for deployments that already publish **Ed25519** joint keys:

1. Run **linked ceremonies** with the same `ceremonyId` and officer roster.
2. Publish **composite public key**: `{ ed25519PublicKey, mlDsa65PublicKey }`.
3. High-value credentials may require **both** threshold signatures (classical + PQ) during migration; verifiers check both.

Hybrid is **not** a single mathematical signature — it is a **coordinated dual C3** with binding in the continuity / credential payload.

---

## 5. Integration with pqforge

| Concern | Owner |
| ------- | ----- |
| ML-DSA keygen, single-party sign/verify | pqforge `PqSignaturePrimitives` |
| Threshold DKG + partial signing rounds | pqthreshold `lib/src/scheme/ml_dsa/` |
| Wrapped share custody | Same `PqWrappedKey` envelope ([TERMINAL.md](TERMINAL.md) §5) |
| Member device hybrid keys | pqforge (unchanged) |

Applications verify organizational credentials with **pqforge** regardless of whether the root was classical-only or PQ threshold.

---

## 6. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial v2 PQ scheme map (ADR-004 M1) |
