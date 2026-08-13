# SERIALIZATION.md

**pqthreshold** — Wire formats, versioning, and domain separation

Status: formative specification  
Audience: implementers, integrators storing shares or transcripts  
Prerequisites: `doc/SCHEMES.md`, `doc/ARCHITECTURE.md`, [PARAMS.md](PARAMS.md)

---

## 1. Purpose

All durable `pqthreshold` objects (`ThresholdParams`, `Share`, `PublicKey`, `PartialSignature`, `Transcript`, ceremony messages) use an explicit, versioned binary format. This document defines the encoding rules so objects cannot be mixed across ceremonies or schemes.

Encoding utilities (`length-prefixed fields`, `uint32`, `uint64`, `concat`) reuse **`PqBytes`** from `pqforge` where applicable. No separate serialization dependency is added.

---

## 2. Design goals

| Goal | Approach |
| ---- | -------- |
| Deterministic encoding | Fixed field order; canonical integer endianness (big-endian) |
| Domain separation | Magic bytes + scheme ID + ceremony ID in object headers |
| Fail closed on parse | Unknown version or scheme → `SerializationError` |
| Compact on disk | Binary primary format; JSON debug export optional later |
| Cross-ceremony safety | `ceremonyId` and `params` bound into every share and partial |

---

## 3. Global conventions

### 3.1 Magic and version header

Every durable object begins with:

```text
PQTH  (4 bytes ASCII)
ver   (1 byte, currently 0x01)
kind  (1 byte object kind, see §4)
scheme (2 bytes, SchemeId enum ordinal, big-endian)
```

Total fixed prefix: **8 bytes** (`PQTH` + ver + kind + scheme).

### 3.2 Object kinds

| `kind` | Type |
| ------ | ---- |
| `0x01` | `ThresholdParams` |
| `0x02` | `Share` |
| `0x03` | `PublicKey` |
| `0x04` | `PartialSignature` |
| `0x05` | `Transcript` |
| `0x06` | `ContinuityProof` |
| `0x10`–`0x1F` | Ceremony round messages — see [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) |

Reserved kinds are rejected until documented in a minor release.

### 3.3 String and byte fields

After the global header, payloads use **`PqBytes.lengthPrefixed`** records:

```text
uint32_be(length) || bytes
```

Multiple fields are concatenated in documented order. Parsing uses `PqBytes.decodeLengthPrefixed`.

### 3.4 Identifiers

| Field | Format |
| ----- | ------ |
| `ceremonyId` | 16 bytes — `PqBytes.randomBytes(16)` at ceremony start; never reused |
| `participantId` | Length-prefixed UTF-8 string (application-assigned, e.g. officer label or public key fingerprint) |

---

## 4. Object layouts (v1)

### 4.1 ThresholdParams

```text
header (§3.1, kind=0x01)
|| uint16_be(t)
|| uint16_be(n)
|| uint32_be(maxParticipants)   // scheme limit, e.g. 255
```

Validation at deserialize: `1 ≤ t ≤ n`, scheme constraints for `frostEd25519V1`.

### 4.2 Share

```text
header (kind=0x02)
|| ceremonyId (16 bytes)
|| params (embedded ThresholdParams bytes, or hash reference — implementer choice; v1 embeds full params)
|| participantId (length-prefixed UTF-8)
|| shareIndex (uint16_be, 1..n)
|| secretShare (length-prefixed, scheme-defined scalar encoding, 32 bytes for Ed25519)
|| verificationData (length-prefixed, Feldman commitments or DKG public share material)
```

Shares deserialized with mismatched `ceremonyId`, `scheme`, or `params` → `WrongCeremony` / `InconsistentShares`.

### 4.3 PublicKey

```text
header (kind=0x03)
|| ceremonyId (16 bytes)
|| params (embedded)
|| publicKeyBytes (length-prefixed, 32 bytes Ed25519 for v1)
```

### 4.4 PartialSignature

```text
header (kind=0x04)
|| ceremonyId (16 bytes)
|| publicKeyFingerprint (32 bytes, SHA-256 of PublicKey canonical bytes)
|| signerIndex (uint16_be)
|| messageBinding (32 bytes, see §5)
|| partialBytes (length-prefixed, FROST binding + hiding + commitment per draft)
```

### 4.5 Transcript

```text
header (kind=0x05)
|| ceremonyId (16 bytes)
|| params (embedded)
|| participantList (length-prefixed UTF-8 JSON array OR repeated participantId fields — v1 uses repeated length-prefixed participantId)
|| entryCount (uint32_be)
|| entries[] each:
     || round (uint8)
     || senderIndex (uint16_be)
     || messageHash (32 bytes, SHA-256 of canonical round message bytes)
     || prevHash (32 bytes, hash chain)
|| footer:
     || outcome (uint8: 0=success, 1=abort)
     || abortReason (length-prefixed UTF-8, empty if success)
     || finalPublicKey (optional, length-prefixed PublicKey bytes)
     || rootHash (32 bytes, SHA-256 over all entry hashes + footer fields)
```

Transcripts store **hashes** of round messages by default (not full message bodies). Applications may archive raw messages separately, keyed by `messageHash`. Canonical message bytes: [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §2.

### 4.6 ContinuityProof (C5 rotation)

```text
header (kind=0x06)
|| oldCeremonyId (16 bytes)
|| newCeremonyId (16 bytes)
|| oldPublicKey (32 bytes)
|| newPublicKey (32 bytes)
|| signedAt (uint64_be unix seconds)
|| thresholdSignature (64 bytes Ed25519 over continuityPayload)
```

**continuityPayload** bytes defined in [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §6.  
Verify: `ThresholdSigner.verify` with **old** `PublicKey` and `continuityPayload`.

---

## 5. Domain-separation string registry (v1)

All protocol hashes prepend a domain tag via `PqBytes.concat([utf8(domain), uint8(0x00), ...])`:

| Domain string | Usage |
| ------------- | ----- |
| `pqthreshold/v1/frost/challenge` | FROST signing challenge |
| `pqthreshold/v1/frost/commitment` | DKG / signing commitments |
| `pqthreshold/v1/feldman/share` | Feldman VSS share derivation |
| `pqthreshold/v1/dkg/session` | DKG round binding |
| `pqthreshold/v1/transcript/entry` | Transcript hash chain |
| `pqthreshold/v1/message-binding` | Bind partial signatures to message + context |

| `pqthreshold/v1/continuity` | C5 continuity signed payload prefix |

**Message binding** for partial signatures:

```text
messageBinding = SHA-256(
  domain "pqthreshold/v1/message-binding"
  || ceremonyId
  || publicKeyBytes
  || message (length-prefixed)
  || optional context (length-prefixed, empty if none)
)
```

New domains require a minor version note; changing an existing domain requires a major version bump.

---

## 6. JSON (debug only)

A `toDebugJson()` / `fromDebugJson()` pair may be provided for development. **JSON is not a durable interchange format for v1** — field ordering and canonicalization are not guaranteed for security-critical storage.

Production storage must use binary canonical bytes defined in this document.

---

## 7. Migration and compatibility

| Change type | Version bump | Requirement |
| ----------- | ------------ | ----------- |
| New object kind | Minor | Document new kind |
| New optional trailing fields | Minor | Old parsers ignore unknown tail if version matches |
| Changed field order or semantics | Major | Migration ceremony (re-share or re-DKG) |
| New scheme ID | Minor or major | New `SchemeId`; old objects remain parseable |

Breaking format changes require notes in `CHANGELOG.md` and a checklist in `doc/CEREMONIES.md` for re-share migration.

---

## 8. Implementation notes

- Use `PqBytes.sha256` for all hashes in this spec.
- Use `PqBytes.constantTimeEquals` when comparing MACs, hashes, or scalar encodings after decode.
- Do not hand-roll varint or JSON canonicalization for durable objects.
- Round messages: [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) (canonical envelope §2).
- Durable objects: this document §4.

---

## 9. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | ContinuityProof kind 0x06; links to PROTOCOL_MESSAGES |
| 2026-08-13 | Initial v1 binary format and domain registry |
