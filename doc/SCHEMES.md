# SCHEMES.md

**pqthreshold** — Algorithm choices, assumptions, and platform support for v1

Status: formative specification (decisions locked for implementation start)  
Audience: implementers, reviewers  
Companion documents: `doc/adr/001-scheme-selection.md`, `doc/SERIALIZATION.md`, `doc/FROST_PROFILE.md`, `doc/PROTOCOL_MESSAGES.md`, `doc/PARAMS.md`, `doc/SECURITY.md`  
**Start here if implementing:** [INDEX.md](INDEX.md)

---

## 1. Purpose

This document records the concrete cryptographic schemes for the initial implementation of `pqthreshold`. All other docs refer to “scheme-dependent” behavior; **this file is the source of truth** for which algorithms v1 uses and why.

Design constraint: **minimal crypto deps, explicit structure**. Cryptography is **pqforge-first** (pointycastle last resort). Protocol structure — state machines, `Result`, validation, codecs — is **swissarmyknife** (`doc/SWISSARMYKNIFE.md`). Only `pqforge` and `swissarmyknife` in `pubspec.yaml`.

---

## 2. v1 scheme stack (summary)

| Capability | Scheme | Standard / reference |
| ---------- | ------ | -------------------- |
| Verifiable secret sharing | **Feldman VSS** over Ed25519 scalar field | Shamir + Feldman commitments |
| Distributed key generation | **Gennaro DKG** (complaint-based) compatible with Ed25519 / FROST keys | GJKR-style multiparty generation |
| Threshold signing | **FROST (Ed25519)** | [draft-irtf-cfrg-frost-15](https://datatracker.ietf.org/doc/draft-irtf-cfrg-frost/) |
| Combined signature format | Standard **64-byte Ed25519** | RFC 8032 — verifiable by ordinary Ed25519 APIs |
| Hash / MAC / encoding | **SHA-256**, **HMAC-SHA-256**, length-prefixed fields | `PqBytes` |
| Ed25519 sign / verify | Combined FROST output, cross-checks | `PqClassical.provider` |
| Symmetric helpers | HKDF-SHA-256 where needed | `PqSymmetricPrimitives` |
| Group / scalar ops (DKG, VSS) | Feldman commitments, FROST round math | pointycastle **last resort** via pqforge export |
| Secure randomness | Platform CSPRNG | `PqRandom` |
| DKG / ceremony control flow | Round states, guards, explicit failures | `StateMachine`, `Result` (**swissarmyknife**) |
| Param / share validation | Composable rules | `Validator` (**swissarmyknife**) |
| Serialization pipelines | Staged encode/decode | `CodecPipeline` (**swissarmyknife**) |
| Secret lifecycle | Wipe on abort/finalize | `Disposable`, `DisposeBag` (**swissarmyknife**) |

### Scheme identifier

v1 production: `frostEd25519V1` (ordinal `0x0001`). v2 adds PQ threshold schemes — see [PQ_SCHEMES.md](PQ_SCHEMES.md) and [adr/004-pq-threshold-schemes.md](adr/004-pq-threshold-schemes.md).

```dart
enum SchemeId {
  frostEd25519V1,        // v1 production
  mlDsa65ThresholdV1,    // v2 primary PQ target (M2)
  // … see PARAMS.md §2
}
```

Future schemes receive new `SchemeId` values and new format-version rules; they do not reuse v1 domain-separation strings.

---

## 3. Rationale

### 3.1 Why FROST (Ed25519)?

- **Verifier compatibility**: The combined FROST signature is a standard Ed25519 signature. Applications (and `pqforge` hybrid verifiers) can validate threshold-produced signatures without threshold-aware verification code.
- **Pure Dart feasibility**: Ed25519 via `PqClassical`; group math for DKG/VSS via pointycastle only where pqforge has no facade
- **Standards track**: FROST is on the IRTF CFRG path with test vectors and clear round structure.
- **Stack alignment**: `pqforge` already uses Ed25519 for hybrid signing (`ML-DSA + Ed25519`). Organizational roots under threshold Ed25519 compose cleanly with member device keys.

### 3.2 Why Feldman VSS?

- Needed for **C2 (dealer-based sharing)** — migrating legacy secrets to threshold control.
- Verification data is compact (commitment vectors); shares are verifiable without revealing the secret.
- Same scalar field as FROST/DKG — one arithmetic stack.

Pedersen VSS (hiding the dealer’s secret polynomial) is **deferred to v2** unless a concrete use case requires it before launch.

### 3.3 Why Gennaro-style DKG?

- Supports **C1 (root DKG)** without a trusted dealer.
- Well-studied complaint phase catches malicious contributions.
- Output keys are compatible with FROST signing.

### 3.4 What v1 explicitly excludes

| Excluded | Reason |
| -------- | ------ |
| ML-DSA / SLH-DSA threshold | Standards and implementations immature; not stable enough for high-assurance v1 |
| ECDSA-P256 threshold | Different curve stack; adds complexity without matching pqforge’s primary Ed25519 path |
| Pedersen VSS | Not required for initial ceremonies; adds generator / discrete-log assumptions in API |
| Proactive share refresh (C6) | Requires PSS or equivalent; deferred to v2 |
| Re-share without full reconstruct (C4-B) | Deferred to v2; v1 documents controlled reconstruct only |

---

## 4. Primitive sourcing (pqforge-first)

`pqthreshold` declares **two runtime dependencies**: `pqforge` and `swissarmyknife` ([adr/002-runtime-dependencies.md](adr/002-runtime-dependencies.md)).

Use pqforge’s **typed APIs first**. Drop to **pointycastle** (exported by pqforge, never added to `pubspec.yaml`) **only** when pqforge does not expose the operation. Do not import `cryptography`, `pqcrypto`, or hybrid/envelope APIs from threshold core modules.

### Sourcing hierarchy

| Priority | Source | Use for |
| -------- | ------ | ------- |
| **1** | `PqBytes` | SHA-256, HMAC-SHA-256, length-prefixed encoding, constant-time compare |
| **1** | `PqRandom` / `PqBytes.randomBytes` | CSPRNG, ceremony IDs |
| **1** | `PqSymmetricPrimitives` | HKDF-SHA-256 and other symmetric helpers pqforge already wraps |
| **1** | `PqClassical.provider` | Ed25519 keygen, sign, verify (combined FROST output, tests, sanity checks) |
| **2** | `pointycastle` via `package:pqforge/pqforge.dart` | **Only when tier 1 lacks it** — e.g. scalar/point arithmetic for Feldman commitments and FROST DKG rounds |
| **Never** | `PqForge` / `PqForgeHybridSigner` / envelopes / sessions | Application layer (`doc/INTEGRATION.md`) |
| **Never** | Direct `pointycastle`, `cryptography`, or `pqcrypto` in `pubspec.yaml` | Duplicates pqforge |

### When pointycastle is justified

FROST and Feldman VSS need **group operations** (commitments, polynomial evaluation, point/scalar mul) that `PqClassical` does not expose today. Those paths may use pointycastle through pqforge’s export. Before adding a new pointycastle call, confirm pqforge has no suitable facade.

**Not** pointycastle candidates (use `PqClassical` instead):

- Combined signature verification after FROST `combine`
- Ed25519 keypair generation for tests
- Standard single-party sign/verify cross-checks

### Import rule

```dart
import 'package:pqforge/pqforge.dart';
// Prefer: PqBytes, PqRandom, PqSymmetricPrimitives, PqClassical
// pointycastle symbols: only with a comment citing the missing pqforge API
```

If a threshold operation repeatedly needs a primitive pqforge should own, open an issue/PR on **pqforge** rather than growing pointycastle usage in `pqthreshold`.

Engineering utilities (state machines, validation, codecs) belong in **swissarmyknife** — see `doc/SWISSARMYKNIFE.md`. Do not reimplement those in `pqthreshold`.

---

## 5. Security assumptions (FROST / Ed25519 v1)

| Assumption | Notes |
| ---------- | ----- |
| Discrete logarithm hardness on Curve25519 | Standard Ed25519 assumption |
| Random oracle model for SHA-256 in FROST binding / challenge | Matches FROST draft |
| `< t` corrupted participants | Standard threshold model |
| RFC 8032 Ed25519 verification for combined signatures | Cofactor handling per Ed25519 rules |
| Secure randomness from `PqRandom` | Same assumption as pqforge |

### Known limitations

- **Pure Dart is not fully constant-time.** Sensitive paths use `PqBytes.constantTimeEquals` and avoid obvious data-dependent branches where practical; this does not match native constant-time guarantees.
- **Web performance**: DKG with large `n` may be slow; see platform matrix below.
- **Not post-quantum**: Long-term quantum resistance for organizational roots depends on application-layer hybrid design with `pqcrypto` / `pqforge`, not on threshold Ed25519 alone.

Scheme-specific security details: [SECURITY.md](SECURITY.md) **Appendix A**.  
Test acceptance: [TEST_VECTORS.md](TEST_VECTORS.md).

---

## 6. Platform support matrix (v1)

| Platform | VSS | DKG | FROST sign | Notes |
| -------- | --- | --- | ---------- | ----- |
| Dart VM / server | ✅ | ✅ | ✅ | Primary target |
| Flutter mobile / desktop | ✅ | ✅ | ✅ | Primary target |
| Web (dart2js / wasm) | ✅ | ⚠️ | ✅ | DKG with `n > 7` may be impractical; document latency |

Maximum recommended `n` for interactive DKG on web: **7** (soft limit; validate in benchmarks).

---

## 7. Ceremony mapping (v1)

| Ceremony | v1 support | Scheme components |
| -------- | ---------- | ----------------- |
| C1 Root DKG | ✅ | Gennaro DKG + FROST-compatible key |
| C2 Dealer sharing | ✅ | Feldman VSS |
| C3 Threshold signing | ✅ | FROST partial sign + combine |
| C4 Recovery (reconstruct) | ✅ | VSS reconstruct (explicit, high-privilege) |
| C4-B Re-share without reconstruct | ❌ v2 | — |
| C5 Rotation | ✅ | C1 + C3 continuity signature |
| C6 Share refresh | ❌ v2 | — |

---

## 8. Test vectors

v1 implementation must include:

- Feldman VSS: `t-1` reconstruct fails, `t` succeeds; malformed commitment rejected
- DKG: simulated `n`-party run produces consistent joint public key
- FROST: alignment with published FROST Ed25519 test vectors where available
- Combined signature verifies via `PqClassical.provider.ed25519Verify`

Vector file layout and formats: [TEST_VECTORS.md](TEST_VECTORS.md).

---

## 9. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial v1 scheme lock: FROST Ed25519 + Feldman VSS + Gennaro DKG |

Changes to the v1 scheme stack require an ADR update and a major-version discussion.
