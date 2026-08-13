# ML_DSA_THRESHOLD_PROFILE.md

**pqthreshold** — Threshold ML-DSA profile (v2, formative)

Status: M2 beta (ML-DSA-44 simulate via Mithril bridge)  
Audience: implementers, cryptographic reviewers  
Prerequisites: [ADR-004](adr/004-pq-threshold-schemes.md), [PQ_SCHEMES.md](PQ_SCHEMES.md), FIPS 204

---

## 1. Goal

Produce **standard FIPS 204 ML-DSA signatures** from a `t`-of-`n` threshold key such that:

```dart
PqSignaturePrimitives.verify(
  algorithm, // mlDsa44 | mlDsa65 | mlDsa87
  jointPublicKey,
  message,
  combinedSignature,
); // true
```

No threshold-aware verifier in applications.

---

## 2. Scheme identifiers

| `SchemeId` | ML-DSA parameter set | Signature size |
| ---------- | -------------------- | -------------- |
| `mlDsa44ThresholdV1` | ML-DSA-44 | 2420 bytes |
| `mlDsa65ThresholdV1` | ML-DSA-65 | 3309 bytes |
| `mlDsa87ThresholdV1` | ML-DSA-87 | 4627 bytes |

Public key sizes match pqforge `PqSignatureAlgorithm` (`publicKeyBytes`).

---

## 3. Reference construction (implementation target)

v2 primary target: **Mithril-class** threshold ML-DSA (replicated / short-share techniques, FIPS 204 compatible output, small-set `n ≤ 8`). Implementation may substitute **TALUS** or Shamir-nonce DKG if online round count or success rate is better, provided:

- Output signatures are **byte-identical** to single-signer ML-DSA for the same key/message
- Security reduction is documented in the review checklist
- Test vectors include cross-verification with pqforge single-party verify

**Explicitly out of scope for profile v1:** dealer Shamir-split of raw `secretKey` bytes followed by reconstruct-and-sign (that is C4 migration only, not C3).

---

## 4. Domain separation

```text
mlDsaThresholdIdentifier = UTF8("pqthreshold-ml-dsa-threshold-v1")
  || 0x00
  || ceremonyId (16)
  || uint16_be(t)
  || uint16_be(n)
  || uint16_be(schemeOrdinal)
  || rosterHash
```

(`rosterHash` same definition as [FROST_PROFILE.md](FROST_PROFILE.md) §5.)

Message binding for signing sessions:

```text
mlDsaMessageBinding = UTF8("pqthreshold/v2/ml-dsa-message-binding")
  || 0x00
  || ceremonyId
  || lengthPrefixed(jointPublicKey)
  || lengthPrefixed(message)
  || lengthPrefixed(context)
```

Hash: SHA-256 via `PqBytes.sha256`.

---

## 5. Protocol outline (C1 / C3)

### C1 — Threshold key generation

1. **Distributed key generation** (preferred): lattice DKG producing joint `(pk, sk_i)` shares without a dealer.
2. **A posteriori sharing** (optional): split existing ML-DSA key per Mithril-compatible sharing; preserves `pk`.

Wire messages use kind bytes `0x20`–`0x2F` (reserved in [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md); tables added at M2).

### C3 — Threshold signing

High-level rounds (exact subKinds at M2):

| Round | Purpose |
| ----- | ------- |
| Offline / preprocessing | Nonce candidates, rejection filtering (BCC-style), commitment material |
| Online 1 | Broadcast masked commitments / partials |
| Online 2 | Coordinator or last signer assembles FIPS 204 signature |

**Coordinator model:** v2.0-beta may use an **honest coordinator** that never sees full `sk` (same trust as FROST combine). Fully malicious-secure MPC is M3+.

### Combine

Local operation: input ≥ `t` valid partials + `jointPublicKey` + `message` → variable-length ML-DSA signature.

---

## 6. PQTH objects (v2 additive)

New durable kinds (additive to `ver=0x01`):

| Kind | Object |
| ---- | ------ |
| `0x07` | `MlDsaPublicKey` — variable-length FIPS 204 public key + ceremony binding |
| `0x08` | `MlDsaPartialSignature` — round material (M2) |

Existing `PublicKey` (`0x03`) remains **Ed25519-only** for v1 compatibility.

---

## 7. Parameter limits

See [PARAMS.md](PARAMS.md) §3.4 — max `n = 8` for ML-DSA schemes.

---

## 8. Test vectors (M2+)

Required before `mlDsa65ThresholdV1` production:

- 2-of-3 simulated threshold sign → pqforge verify
- Wrong message / wrong ceremony / `t-1` partials fail closed
- Cross-check one vector against reference implementation (if available)

---

## 9. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial profile (ADR-004 M1) |
