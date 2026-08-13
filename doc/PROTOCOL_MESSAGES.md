# PROTOCOL_MESSAGES.md

**pqthreshold** — On-the-wire protocol message formats (v1)

Status: formative specification  
Audience: implementers  
Prerequisites: [INDEX.md](INDEX.md), [SERIALIZATION.md](SERIALIZATION.md) §3, [PARAMS.md](PARAMS.md), [FROST_PROFILE.md](FROST_PROFILE.md)

---

## 1. Purpose

[SERIALIZATION.md](SERIALIZATION.md) defines **stored objects** (`Share`, `PublicKey`, …). **This document** defines **messages exchanged during protocols** (DKG rounds, FROST signing, Feldman distribution).

Every protocol message uses the global **`PQTH` header** ([SERIALIZATION.md](SERIALIZATION.md) §3.1) with **`kind` in `0x10`–`0x1F`** for Ed25519/FROST/DKG, and **`0x20`–`0x22`** for ML-DSA threshold signing (v2). A **subKind** byte immediately after the header selects the message type.

---

## 2. Common message envelope

```text
PQTH (4)
ver  (1)  = 0x01
kind (1)  = 0x10..0x1F  (see tables below)
scheme (2) = 0x0001 (frostEd25519V1)
subKind (1)
ceremonyId (16)
senderIndex (uint16_be)   // 1..n
payload (length-prefixed) // message-specific
```

**Canonical message bytes** = entire envelope above (used for transcript `messageHash`).

Parsing rules:

- Wrong `scheme` or `ceremonyId` → reject (`WrongCeremony`)
- `senderIndex` outside `1..n` → reject
- Unknown `subKind` → `SerializationError`

Encoding: `PqBytes.lengthPrefixed` for payload; integers big-endian unless noted.

---

## 3. DKG messages (C1)

Identifier for DKG hashing:

```text
dkgIdentifier = UTF8("pqthreshold-dkg-ed25519-v1")
  || 0x00 || ceremonyId || uint16_be(t) || uint16_be(n) || rosterHash
```

(`rosterHash` defined in [FROST_PROFILE.md](FROST_PROFILE.md) §5.)

### 3.1 State machine (per participant)

Maps to swissarmyknife `StateMachine` ([SWISSARMYKNIFE.md](SWISSARMYKNIFE.md) §3.5):

```text
setup
  → round1Broadcast     (publish DkgRound1Package)
  → round2Distribute    (send DkgRound2Package to each peer)
  → round3Complaints    (optional DkgComplaint / DkgResponse)
  → finalized | aborted
```

| State | Accepts subKinds | Emits |
| ----- | ---------------- | ----- |
| setup | — | Round1 after local poly generated |
| round1Broadcast | `0x01` from all peers | Round2 to each **j** |
| round2Distribute | `0x02` addressed to self | complaints if verify fails |
| round3Complaints | `0x03`, `0x04` | finalize or abort |
| finalized | — | (CeremonySession.complete) |

### 3.2 SubKind table — DKG

| subKind | Name | kind byte |
| ------- | ---- | --------- |
| `0x01` | `DkgRound1Package` | `0x10` |
| `0x02` | `DkgRound2Package` | `0x11` |
| `0x03` | `DkgComplaint` | `0x12` |
| `0x04` | `DkgResponse` | `0x13` |
| `0x05` | `DkgFinalizeAnnouncement` | `0x14` |

### 3.3 DkgRound1Package (subKind 0x01, kind 0x10)

Participant **P** sends Feldman commitments to its degree-(t-1) polynomial:

```text
envelope (§2)
payload:
  || coeffCount (uint8) = t
  || commitments[t] (each 32-byte compressed point)
```

### 3.4 DkgRound2Package (subKind 0x02, kind 0x11)

**P** sends share scalar to participant **recipientIndex**:

```text
envelope (§2) — senderIndex = P
payload:
  || recipientIndex (uint16_be)
  || shareScalar (32 bytes, little-endian mod L)
```

Only the recipient with `participantIndex == recipientIndex` processes the share. Others ignore.

Recipient verifies share against sender’s Round1 commitments ([FROST_PROFILE.md](FROST_PROFILE.md) §6.2).

### 3.5 DkgComplaint (subKind 0x03, kind 0x12)

```text
payload:
  || accusedIndex (uint16_be)
  || reasonCode (uint8)  // 1=share verify fail, 2=missing round1, 3=other
  || optionalData (length-prefixed, may be empty)
```

### 3.6 DkgResponse (subKind 0x04, kind 0x13)

Accused participant reproduces justification per Gennaro (v1: re-broadcast consistent Round1 + share to complainant):

```text
payload:
  || complainantIndex (uint16_be)
  || embedded Round1 or share proof (length-prefixed)
```

If complaints cannot be resolved → **`CeremonyAborted`**; new `ceremonyId` required for retry ([CEREMONIES.md](CEREMONIES.md) §5).

### 3.7 DkgFinalizeAnnouncement (subKind 0x05, kind 0x14)

Optional broadcast that participant has computed **PK** and **sk_self**:

```text
payload:
  || jointPublicKey (32 bytes)
  || fingerprint (32 bytes, SHA-256 of PublicKey canonical bytes)
```

All honest parties must derive the same **jointPublicKey** before `CeremonySession.finalize()`.

### 3.8 DKG output → stored objects

On success, each party builds:

- `Share` — [SERIALIZATION.md](SERIALIZATION.md) §4.2 with `secretShare` = final **sk_j**, `verificationData` = Feldman vector for own combined share (or joint PK material)
- `PublicKey` — §4.3 with `publicKeyBytes` = **PK**
- `Transcript` — §4.5

---

## 4. Feldman VSS messages (C2)

Dealer model: one dealer, **n** recipients. No multi-round DKG.

### 4.1 SubKind table — Feldman

| subKind | Name | kind byte |
| ------- | ---- | --------- |
| `0x01` | `FeldmanPublicData` | `0x18` |
| `0x02` | `FeldmanShareDelivery` | `0x19` |

### 4.2 FeldmanPublicData (subKind 0x01, kind 0x18)

Broadcast once by dealer:

```text
envelope (§2) — senderIndex = 0 is INVALID; dealer uses index 1 or dedicated dealer index in 1..n
payload:
  || coeffCount (uint8) = t
  || commitments[t] (32 bytes each)
  || jointPublicKey (32 bytes)  // C_0 · B encoded
```

### 4.3 FeldmanShareDelivery (subKind 0x02, kind 0x19)

To recipient **recipientIndex**:

```text
payload:
  || recipientIndex (uint16_be)
  || shareScalar (32 bytes LE)
```

Recipient verifies via §6.2 in [FROST_PROFILE.md](FROST_PROFILE.md), then persists `Share` ([SERIALIZATION.md](SERIALIZATION.md) §4.2).

### 4.4 Reconstruction (C4-A)

No wire message — local operation on **≥ t** stored `Share` objects with matching `ceremonyId` and `params`. Output: 32-byte secret scalar; wipe after use ([CEREMONIES.md](CEREMONIES.md) §8).

---

## 5. FROST signing messages (C3)

See [FROST_PROFILE.md](FROST_PROFILE.md) §7 for cryptography.

**Signing session id:**

```text
signSessionId = frostIdentifier (FROST_PROFILE §5)
  || messageBinding (32 bytes, SERIALIZATION §5)
```

One signing session per `(ceremonyId, messageBinding)` pair.

### 5.1 SubKind table — FROST

| subKind | Name | kind byte |
| ------- | ---- | --------- |
| `0x01` | `FrostSigningRound1` | `0x15` |
| `0x02` | `FrostSigningRound2` | `0x16` |

### 5.2 FrostSigningRound1 (subKind 0x01, kind 0x15)

```text
envelope (§2)
payload:
  || messageBinding (32 bytes)
  || hidingCommitment (32 bytes)   // R_i
  || bindingCommitment (32 bytes)  // D_i
```

Collect **≥ t** distinct `senderIndex` values before Round 2.

### 5.3 FrostSigningRound2 (subKind 0x02, kind 0x16)

```text
payload:
  || messageBinding (32 bytes)
  || partialScalar (32 bytes LE)   // z_i
```

Coordinator validates each partial against Round1 commitments and roster; invalid → `InvalidPartialSignature`.

### 5.4 Combine (local)

Not a wire message. Input: **≥ t** valid Round2 messages + `PublicKey` + `message`.  
Output: **64-byte** Ed25519 signature → verify with `PqClassical.provider.ed25519Verify`.

Persist coordinator result as needed; store partials in `PartialSignature` ([SERIALIZATION.md](SERIALIZATION.md) §4.4) if archiving.

---

## 6. ML-DSA threshold signing (C3-PQ, v2)

See [ML_DSA_THRESHOLD_PROFILE.md](ML_DSA_THRESHOLD_PROFILE.md) for cryptography and domain separation.

**Signing session id** (32 bytes, carried in every ML-DSA wire envelope):

```text
sessionId = SHAKE256("th-ml-dsa-session-v1" || sessionEntropy || pk || act || message)[0..32]
```

(`sessionEntropy` is coordinator-generated; M3 beta uses Mithril bridge `wire_sign`.)

### 6.1 Envelope extension

ML-DSA signing messages extend §2 with **`sessionId (32)`** before the length-prefixed payload:

```text
PQTH (4)
ver  (1)  = 0x01
kind (1)  = 0x20..0x22
scheme (2) = ML-DSA threshold wire ordinal (see PARAMS.md)
subKind (1)
ceremonyId (16)
senderIndex (uint16_be)   // 1..n
sessionId (32)
payloadLen (uint32_be)
payload
```

### 6.2 SubKind table — ML-DSA

| subKind | Name | kind byte |
| ------- | ---- | --------- |
| `0x01` | `MlDsaSigningRound1` (commitment hash) | `0x20` |
| `0x02` | `MlDsaSigningRound2` (reveal) | `0x21` |
| `0x03` | `MlDsaSigningRound3` (response) | `0x22` |

### 6.3 MlDsaSigningRound1 (subKind 0x01, kind 0x20)

```text
payload:
  || commitmentHash (32 bytes)   // Round1 hash from Mithril sign::round1
```

### 6.4 MlDsaSigningRound2 (subKind 0x02, kind 0x21)

```text
payload:
  || revealBytes (variable)      // packed w commitments per Mithril sign::round2
```

### 6.5 MlDsaSigningRound3 (subKind 0x03, kind 0x22)

```text
payload:
  || responseBytes (variable)    // FIPS 204 `pack_z` per slot: k_reps × (L × POLYZ_PACKEDBYTES)
```

### 6.6 Combine (local / coordinator)

Not a wire message in M3 beta. Coordinator aggregates Round2 reveals and Round3 responses, then combines per Mithril `coordinator::combine`. Output: **FIPS 204 ML-DSA signature** → verify with `MlDsaThresholdVerifier` / pqforge.

Dir-transport filenames (CLI `sign ml-dsa run --wire-dir`):

```text
wire-dir/round1/from-{senderIndex}.wire
wire-dir/round2/from-{senderIndex}.wire
wire-dir/round3/from-{senderIndex}.wire
```

---

## 7. Continuity proof (C5 rotation)

Stored object and optional wire artifact. Uses **`kind = 0x06`** (durable object, not `0x10` range):

See [SERIALIZATION.md](SERIALIZATION.md) §4.6.

Conceptual content signed under C3:

```text
continuityPayload = UTF8("pqthreshold-continuity-v1")
  || 0x00
  || oldPublicKey (32)
  || newPublicKey (32)
  || uint64_be(unixSeconds)
  || ceremonyId_old (16)
  || ceremonyId_new (16)
```

Threshold-sign `continuityPayload` with **old** key shares; embed **64-byte** signature in `ContinuityProof`.

---

## 8. Message flow diagrams

### C1 DKG (simplified)

```text
Each P:  Round1 broadcast ──────────────────────────► all
Each P:  Round2 ──► peer j (n-1 messages)
Optional: Complaint / Response
Each P:  FinalizeAnnouncement ───────────────────► all
Local:   Share + PublicKey + Transcript
```

### C3 Signing

```text
Each signer:  FrostSigningRound1 ─────────────────► coordinator
Coordinator:  (wait ≥ t)
Each signer:  FrostSigningRound2 ─────────────────► coordinator
Coordinator:  combine → Ed25519 signature → verify
```

### C3-PQ ML-DSA (M3 beta — coordinator exports wire)

```text
Each signer:  MlDsaSigningRound1 ────────────────► coordinator
Coordinator:  aggregate Round1 hashes
Each signer:  MlDsaSigningRound2 ────────────────► coordinator
Coordinator:  aggregate commitments → w finals
Each signer:  MlDsaSigningRound3 ────────────────► coordinator
Coordinator:  aggregate responses → combine → ML-DSA signature → verify
```

---

## 9. Implementation checklist

- [ ] Parse envelope before crypto ([SWISSARMYKNIFE.md](SWISSARMYKNIFE.md) `CodecPipeline`)
- [ ] Reject duplicate Round1 from same `senderIndex`
- [ ] Transcript logs `SHA-256(canonical envelope)` only ([SERIALIZATION.md](SERIALIZATION.md) §4.5)
- [ ] Never include `shareScalar` in transcript
- [ ] Map internal `Result` failures to [API.md](API.md) §5 at public boundary

---

## 10. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | ML-DSA threshold wire messages §6 (`0x20`–`0x22`) |
| 2026-08-13 | Initial DKG, Feldman, FROST, continuity payload |
