# FROST_PROFILE.md

**pqthreshold** — FROST Ed25519 ciphersuite profile for v1

Status: formative specification  
Audience: implementers  
Prerequisites: [SCHEMES.md](SCHEMES.md), [PARAMS.md](PARAMS.md)  
Wire bytes: [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §5  
Stored objects: [SERIALIZATION.md](SERIALIZATION.md) §4.4

---

## 1. Purpose

This document pins the **exact FROST profile** for `SchemeId.frostEd25519V1`. Implementers must not infer details from the FROST draft alone — use this file plus [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md).

---

## 2. Normative references

| Reference | Use |
| --------- | --- |
| [draft-irtf-cfrg-frost-15](https://datatracker.ietf.org/doc/draft-irtf-cfrg-frost/) | Two-round FROST signing, DKG structure |
| [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032) | Ed25519 signature encoding and verification |
| pqthreshold [SERIALIZATION.md](SERIALIZATION.md) §5 | Application message binding (SHA-256 domains) |

**Profile name:** `pqthreshold-frost-ed25519-v1`  
**Maps to draft ciphersuite:** FROST Ed25519 with **SHA-512** for protocol hashes `H1`, `H2`, `H3` (per draft §5.4 / Ed25519 ciphersuite).

---

## 3. Cryptographic setting

| Parameter | Value |
| --------- | ----- |
| Curve | Ed25519 (Edwards curve25519) |
| Group generator | Ed25519 base point **B** (RFC 8032) |
| Scalar field | Integers mod **L** (Ed25519 subgroup order) |
| Scalar encoding | 32-byte little-endian, reduced mod **L** |
| Point encoding | 32-byte compressed Edwards **y** with sign bit (RFC 8032) |
| Group public key | 32-byte Ed25519 public key (standard encoding) |
| Combined signature | 64-byte Ed25519 **R \|\| S** (RFC 8032) |

Group/scalar operations: pqforge-first; pointycastle via pqforge only where `PqClassical` lacks group APIs ([SCHEMES.md](SCHEMES.md) §4).

---

## 4. What v1 implements from the draft

| Draft feature | v1 |
| ------------- | -- |
| Two-round threshold signing | ✅ |
| `t`-of-`n` Shamir secret sharing over **L** | ✅ |
| Gennaro-style DKG with complaints | ✅ ([PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §3) |
| FROST rerandomization / ROAST | ❌ |
| Parallel signing sessions | ❌ — one signing session per `ceremonyId` + message binding |
| Identifier / context per draft | ✅ — see §5 |

---

## 5. Identifiers and domain separation

FROST draft **identifier** (binding the protocol transcript):

```text
frostIdentifier = UTF8("pqthreshold-frost-ed25519-v1")
  || 0x00
  || ceremonyId (16 bytes)
  || uint16_be(t)
  || uint16_be(n)
  || rosterHash (32 bytes)
```

**rosterHash** = `SHA-256( length-prefixed sorted participantIndex uint16_be values for indices 1..n )`.

Application **message** binding (separate from FROST internal hashes):

```text
messageBinding = SHA-256( ... )   // full definition: SERIALIZATION.md §5
```

FROST challenge and commitment hashes use **SHA-512** with prefix **`frostIdentifier`** prepended to draft-defined inputs (H1, H2, H3 in draft terminology).

Implementers: map draft hash calls to:

```text
H1(msg) = SHA-512( frostIdentifier || msg )
H2(msg) = SHA-512( frostIdentifier || 0x02 || msg )
H3(msg) = SHA-512( frostIdentifier || 0x03 || msg )
```

(Distinct single-byte tags avoid cross-type collisions within the profile.)

---

## 6. Secret sharing (Feldman + DKG)

### 6.1 Polynomial

- Dealer or DKG participant **P** holds polynomial **f** of degree **`t - 1`** over **Z_L**.
- Coefficients **a_0 … a_{t-1}** with **a_0** the participant’s secret contribution.
- Share for index **i**: **s_i = f(i)** where **i ∈ {1,…,n}** ([PARAMS.md](PARAMS.md) §4).

### 6.2 Feldman commitments

For each coefficient **a_k**:

```text
C_k = a_k · B   (scalar mult on Ed25519)
```

**Verification data** = serialized list `[C_0, C_1, …, C_{t-1}]` (each 32 bytes).  
Share verification for index **i**:

```text
s_i · B  ==  sum_{k=0}^{t-1} (i^k mod L) · C_k
```

Use constant-time scalar ops where practical; compare points with `PqBytes.constantTimeEquals` on encodings.

### 6.3 Joint keys after DKG

- Each participant **j** final secret share: **sk_j = sum_i f_i(j)** mod **L**.
- Joint public key: **PK = sum_i (a_0 of participant i) · B** = sum of **C_0** from each honest DKG package.

Details: [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §3.

---

## 7. FROST signing rounds (summary)

Full byte layouts: [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §5.

### Round 1 — commitments

Each signer **i** with share **sk_i** picks hiding **r_i** and binding **d_i** scalars; sends commitments **R_i = r_i·B**, **D_i = d_i·B**.

### Round 2 — partial signatures

After all commitments, compute binding factors and challenge **c** per draft; each signer publishes **z_i** scalar (partial).

### Combine

Coordinator with at least **t** valid partials computes **64-byte Ed25519 signature** (**R**, **S**).

### Verify

```dart
await PqClassical.provider.ed25519Verify(
  publicKey: jointPublicKey,
  message: message,
  signature: combinedSignature,
);
```

**Do not** implement a separate Ed25519 verifier in pqthreshold for v1.

---

## 8. Key generation vs signing identifiers

| Phase | Identifier includes |
| ----- | --------------------- |
| DKG | `dkgIdentifier` — see [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §3.1 |
| Signing | `frostIdentifier` — §5 above |

DKG and signing use **different** domain prefixes so DKG bytes cannot be replayed as signing messages.

---

## 9. Test vectors

| Source | Purpose |
| ------ | ------- |
| Draft FROST Ed25519 vectors (when reproduced in repo) | Round-trip signing |
| Locally generated vectors | DKG 2-of-3, 3-of-5; Feldman `t-1` fail |
| File layout | [TEST_VECTORS.md](TEST_VECTORS.md) |

Pass criteria: combined signature verifies via `PqClassical.provider.ed25519Verify`.

---

## 10. Out of scope (v1)

- ROAST / identifiable abort
- Taproot / secp256k1 FROST
- Pre-processing keys
- Post-quantum FROST

---

## 11. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial profile pin for frostEd25519V1 |
