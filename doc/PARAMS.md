# PARAMS.md

**pqthreshold** — Threshold parameters, indices, and validation rules

Status: formative specification  
Audience: implementers  
Prerequisites: [SCHEMES.md](SCHEMES.md)  
See also: [SERIALIZATION.md](SERIALIZATION.md) §4.1, [API.md](API.md) §3.1, [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §2

---

## 1. Purpose

This document is the **single source of truth** for numeric and structural constraints on `ThresholdParams` and participant identity. Every validator, deserializer, and ceremony must use these rules.

---

## 2. SchemeId (v1)

| Ordinal (uint16 BE) | Name | Status |
| ------------------- | ---- | ------ |
| `0x0001` | `frostEd25519V1` | Only production scheme in v1 |

Unknown ordinals → `SerializationError` on decode.

```dart
enum SchemeId {
  frostEd25519V1, // ordinal 1
}
```

---

## 3. ThresholdParams rules

### 3.1 Fields

| Field | Type | Description |
| ----- | ---- | ----------- |
| `t` | `int` | Quorum size; minimum honest shares to sign or reconstruct |
| `n` | `int` | Number of participants / shares |
| `scheme` | `SchemeId` | Must be `frostEd25519V1` in v1 |

### 3.2 Hard limits (`frostEd25519V1`)

| Rule | Value | Error |
| ---- | ----- | ----- |
| Minimum `t` | `1` | `InvalidParams` — use only in tests |
| Maximum `t` | `n` | `InvalidParams` |
| Minimum `n` | `1` | `InvalidParams` |
| Maximum `n` | **`255`** | `InvalidParams` — Shamir index is uint8-friendly |
| `t` ≤ `n` | required | `InvalidParams` |

Production deployments should use **`t ≥ 2`** (see [SECURITY.md](SECURITY.md) §7).

### 3.3 Soft limits (documentation only, not enforced)

| Context | Recommendation |
| ------- | -------------- |
| Web DKG | Prefer `n ≤ 7` ([SCHEMES.md](SCHEMES.md) §6) |
| High-value roots | Common `(t,n)`: (2,3), (3,5), (3,7) ([CEREMONIES.md](CEREMONIES.md)) |

### 3.4 Serialized form

See [SERIALIZATION.md](SERIALIZATION.md) §4.1. Field `maxParticipants` in the blob is **`255`** for `frostEd25519V1`.

---

## 4. Participant identity

Two parallel identifiers — do not conflate them.

| Field | Used for | Format |
| ----- | -------- | ------ |
| **participantIndex** | Shamir evaluation **x = index**; FROST roster; message `senderIndex` | Integer **`1` through `n`**, unique per ceremony |
| **participantId** | Human/app label; transcript; stored on `Share` | UTF-8 string, length-prefixed; max **256 bytes** UTF-8 |

### 4.1 Index rules

- Indices are **1-based** everywhere (not 0-based).
- Each participant in a ceremony has exactly one index in `1..n`.
- Duplicate indices in one ceremony → `CeremonyAborted` / `InconsistentShares`.
- Index **`0`** is reserved and **invalid** in v1 messages and shares.

### 4.2 participantId rules

- Application-assigned; library does not parse format.
- Empty string → `InvalidParams`.
- Same `participantId` with different indices in one ceremony is allowed (e.g. renamed officers) but discouraged operationally.

---

## 5. ceremonyId

| Rule | Value |
| ---- | ----- |
| Length | **16 bytes** |
| Generation | `PqBytes.randomBytes(16)` at ceremony start |
| Reuse | **Forbidden** — new ceremony must use new id |
| All-zero | **Invalid** |

Every `Share`, `PublicKey`, `PartialSignature`, protocol message, and `Transcript` for a run must carry the same `ceremonyId`.

---

## 6. Validation implementation

Use swissarmyknife `Validator` internally; public factory throws `InvalidParams`.

```dart
// Illustrative — implement in lib/src/params/
Validator<(int t, int n)> frostEd25519V1ParamsValidator() {
  return Validator<(int, int)>()
      .custom((p) => p.$1 >= 1, 't must be >= 1')
      .custom((p) => p.$2 >= 1, 'n must be >= 1')
      .custom((p) => p.$1 <= p.$2, 't must be <= n')
      .custom((p) => p.$2 <= 255, 'n must be <= 255 for frostEd25519V1');
}
```

---

## 7. Cross-document index

| Topic | Document |
| ----- | -------- |
| API type | [API.md](API.md) §3.1 |
| Binary encoding | [SERIALIZATION.md](SERIALIZATION.md) §4.1 |
| DKG roster in messages | [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §2 |
| Policy guidance for choosing t/n | [SECURITY.md](SECURITY.md) §7 |

---

## 8. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial params and index rules |
