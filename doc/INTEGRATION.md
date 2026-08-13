# INTEGRATION.md

**pqthreshold** — Working with `pqcrypto`, `pqforge`, and applications (including Panthalassa-style vaults)

Status: formative specification  
Audience: application developers, platform integrators, security reviewers  
**Implementers:** [INDEX.md](INDEX.md)  
Prerequisites: `ARCHITECTURE.md`, `CEREMONIES.md`, `SECURITY.md`

---

## 1. Purpose

`pqthreshold` is deliberately small. It does not replace single-party cryptography, sealed envelopes, sessions, or application policy. This document explains **how to compose it** with the rest of a high-assurance stack so that:

- Organizational / enclave roots are generated and used under threshold control
- Day-to-day device keys and sealing remain on the existing single-party path
- Signatures produced by a quorum are verifiable by ordinary verification code
- Recovery and rotation stay auditable and fail-closed

The primary companions are:

| Package | Role in the composition |
| --------- | ------------------------- |
| [`pqcrypto`](https://pub.dev/packages/pqcrypto) | Single-party ML-KEM, ML-DSA, SLH-DSA (and related) primitives |
| [`pqforge`](https://pub.dev/packages/pqforge) | Hybrid sealing, sessions, envelopes, application recipes, verification helpers |
| **`pqthreshold`** | Distributed key generation, threshold signing, multi-party ceremonies |
| Application | Transport, identity, policy, secure storage of shares, UX, enclave rules |

---

## 2. Responsibility split (non-negotiable)

| Concern | Owner |
| --------- | -------- |
| VSS / DKG / threshold signature cryptography | `pqthreshold` |
| Single-party PQC operations | `pqcrypto` / `pqforge` |
| Hybrid KEM-DEM sealing, secure sessions, `.pqfs`-style envelopes | `pqforge` (or application equivalent) |
| Participant authentication & transport | Application |
| Storage of private shares | Application (`flutter_secure_storage`, HSM, platform keystore, etc.) |
| Choice of `t`/`n` and ceremony policy | Application |
| Continuity policy (when to rotate, who may recover) | Application |
| Parsing / content-id / rendering | Application (e.g. `panthalassa_parsers`) |

`pqthreshold` never opens network connections, never talks to a server, and never decides who is allowed to participate.

---

## 3. Integration patterns

### 3.1 Pattern A — Threshold organizational root + single-party device keys (recommended)

This is the pattern that matches closed-enclave / Vault-style designs.

```text
┌─────────────────────────────────────────────────────────┐
│                     Organization / Enclave              │
│                                                         │
│   Threshold root (pqthreshold DKG)                      │
│   • Joint PublicKey                                     │
│   • Per-officer Shares (t-of-n)                         │
│   • Used for: membership credentials, continuity,       │
│     high-value attestations, root-level signatures      │
└───────────────────────────┬─────────────────────────────┘
                            │ issues / attests
                            ▼
┌─────────────────────────────────────────────────────────┐
│                     Member device                       │
│                                                         │
│   Single-party Key Bundle (pqforge / pqcrypto)          │
│   • Identity signing key (ML-DSA + Ed25519)             │
│   • Sealing key (ML-KEM + X25519)                       │
│   • Prekeys, day-to-day seal/sign/session               │
└─────────────────────────────────────────────────────────┘
```

**How the pieces meet**

1. Enclave officers run **C1 Root DKG Ceremony** (`CEREMONIES.md`) → joint root PublicKey + shares.
2. Root (via threshold signing) issues membership credentials or attests member public bundles.
3. Each member device runs ordinary `pqforge` keygen and uses single-party seal/sign/session for daily traffic.
4. Verifiers trust member keys either by:
   - pinning, or
   - validating a credential / attestation signed by the threshold root.

`pqthreshold` is used rarely (root ceremonies, high-value signatures, rotation).  
`pqforge` is used constantly (every message).

---

### 3.2 Pattern B — Threshold-only high-value signing

Some actions (legal instruments, firmware releases, root policy changes) must never be signable by a single device.

```text
Message / artifact
        │
        ▼
pqthreshold threshold signing (quorum of shares)
        │
        ▼
Combined Signature  ──verify──►  ordinary verifier (pqforge or application)
```

The combined signature is handed to existing verification paths.  
No change is required in `pqforge` verification APIs if the signature format is the ordinary one expected by the verifier.

---

### 3.3 Pattern C — Hybrid continuity (threshold root attests single-party keys)

When a member rotates a device key:

1. Member produces a new single-party public bundle (`pqforge`).
2. Optionally, the threshold root co-signs or issues a fresh membership credential over the new bundle.
3. Relying parties update pins only after validating the root’s threshold signature / credential.

This keeps device keys agile while the organizational root remains under quorum control.

---

### 3.4 Pattern D — Recovery of last resort

Shares live on separate officers’ devices (or offline media).  
If policy authorizes recovery:

1. Run **C4 Recovery Ceremony**.
2. Either re-share to a new committee or perform a controlled reconstruction.
3. Archive the transcript; wipe ephemeral reconstructed material.

Application code must enforce that reconstruction is exceptional, multi-person, and logged.

---

## 4. Concrete composition with pqforge

### 4.1 What pqforge continues to own

- Hybrid key agreement and secure sessions  
- KEM-DEM sealing / unsealing (`.pqfs` or equivalent)  
- Single-party sign / verify  
- Envelope formats, streaming, multi-recipient sealing  
- CLI and application recipes  

See **[TERMINAL.md](TERMINAL.md)** for the unified terminal runbook: how `pqforge keygen` / wrap / inspect compose with planned `pqthreshold` ceremony commands, shared custody (`PqWrappedKey`), and on-disk layout.

### 4.2 What pqthreshold adds

- `DistributedKeyGeneration` / ceremony sessions  
- `Share` lifecycle  
- `ThresholdSigner.signPartial` / `combine` / `verify`  
- Transcript objects for audit  

### 4.3 Glue points

| Glue | Direction |
| ------ | ----------- |
| Threshold PublicKey → pqforge-style verifier | Application passes the joint public key into existing verify APIs (or a thin adapter) |
| Threshold signature → envelope / credential | Application embeds the combined signature where a normal signature is expected |
| Continuity proof | Threshold signature over `(oldPk, newPk, context)` produced by `pqthreshold`, stored/verified by application |
| Membership credential | Content may be a W3C VC or custom structure; **signature** on it can be a threshold signature |

**Dependency model:** `pqthreshold` depends on **`pqforge`** (crypto) and **`swissarmyknife`** (structure). pqforge supplies hashing, randomness, and Ed25519; swissarmyknife supplies DKG state machines, internal `Result` flow, validators, and codecs. Neither replaces the other. See `doc/adr/002-runtime-dependencies.md`, `doc/SCHEMES.md` §4, and `doc/SWISSARMYKNIFE.md`.

Combined v1 signatures are **standard 64-byte Ed25519** and verify through **`PqClassical.provider.ed25519Verify`** without threshold-specific adapters.

---

## 5. Composition with pqcrypto

Use `pqcrypto` when you need raw single-party ML-KEM / ML-DSA / SLH-DSA without the higher-level recipes of `pqforge`.

Typical split:

- Device identity & sealing keys → `pqcrypto` or `pqforge`  
- Organizational root → `pqthreshold`  
- Verification of root signatures → application code using the joint public key  

If a future threshold scheme produces signatures that are byte-compatible with a `pqcrypto` verification path, the application can call that path directly.

---

## 6. Application integration checklist

### 6.1 Key generation (member device)

- [ ] Use `pqforge` (or `pqcrypto`) for on-device identity + sealing keygen  
- [ ] Store private keys only in platform secure storage  
- [ ] Publish public bundle + (optional) membership credential  

### 6.2 Enclave / organizational root

- [ ] Agree `t`, `n`, participant set, scheme  
- [ ] Run C1 Root DKG Ceremony  
- [ ] Store each officer’s share in secure storage (separate devices)  
- [ ] Archive transcript  
- [ ] Publish joint PublicKey to the enclave directory / policy store  

### 6.3 Issuing membership / attestation

- [ ] Construct credential / attestation bytes  
- [ ] Threshold-sign with quorum of root shares (C3)  
- [ ] Distribute credential to member; publish as needed  

### 6.4 Day-to-day sealing

- [ ] Unchanged: sender seals to recipient’s single-party sealing key via `pqforge`  
- [ ] Server still sees only opaque envelopes  

### 6.5 High-value actions

- [ ] Require threshold signature from the organizational root  
- [ ] Verify with the joint PublicKey before accepting the action  

### 6.6 Rotation

- [ ] Run C5 Rotation Ceremony  
- [ ] Publish continuity proof  
- [ ] Update relying parties after proof validation  
- [ ] Retire old shares under policy  

### 6.7 Storage map (illustrative)

| Material | Storage |
| ---------- | --------- |
| Member identity / sealing secrets | Device secure storage (`flutter_secure_storage`, etc.) |
| Officer threshold shares | Officer device secure storage or offline medium |
| Joint PublicKey | Public directory / enclave config |
| Transcripts | Append-only audit log |
| Continuity proofs | Public or enclave-scoped store |

---

## 7. Server / zero-knowledge considerations

In a Panthalassa-style architecture:

- The server still stores **only** accounts, public keys, credentials, public prekeys, and opaque envelopes  
- Threshold shares **never** go to the server  
- Joint PublicKey and membership credentials (public) may be stored  
- Continuity proofs may be stored  
- Ceremonies run **client-side** (or on air-gapped officer machines); the server is not a ceremony participant unless explicitly designed as one (not recommended for roots)

This preserves the zero-knowledge property: the server cannot sign as the root, cannot reconstruct shares, and cannot unseal content.

---

## 8. Error handling across boundaries

| Failure | Where it surfaces | Application action |
| --------- | ------------------- | -------------------- |
| Insufficient partial signatures | `pqthreshold` | Abort action; request more officers |
| Inconsistent shares / transcript | `pqthreshold` | Abort ceremony; start new ceremony ID |
| Membership credential signature invalid | Application / verify path | Reject member or require re-issuance |
| Continuity proof invalid | Application | Reject rotation; keep old PublicKey |
| Share missing after device loss | Application policy | Trigger C4 or C5 with remaining quorum |

Never “fall back” to a single share or a reconstructed secret for convenience.

---

## 9. Versioning and compatibility

- `pqthreshold` public types used in durable storage (`Share`, `PublicKey`, transcripts) are versioned  
- Application must store scheme + format version alongside shares  
- Combined signatures should remain verifiable by the verification path the application already uses; if a scheme produces a non-standard encoding, supply a thin adapter rather than forking `pqforge`  
- Breaking changes in share format require a documented migration / re-share ceremony  

---

## 10. Testing integrations

Recommended test layers:

1. **Unit** — `pqthreshold` alone (DKG, sign, combine, fail-closed cases)  
2. **Composition** — threshold signature verified by the same code path that verifies single-party signatures  
3. **Ceremony simulation** — multiple in-process participants running C1 → C3 → verify  
4. **Application** — membership credential issued under threshold root, accepted by a member device, rejected when quorum is missing  
5. **Negative** — lost share, aborted DKG, continuity proof with wrong old key  

---

## 11. Minimal integration sketch (illustrative)

```dart
// 1) Officers run DKG (pseudo-code)
final params = ThresholdParams.tOfN(t: 3, n: 5);
final outcome = await RootCeremony.run(params, transport: myTransport);
await secureStore.saveShare(outcome.myShare);
await directory.publishRoot(outcome.publicKey, outcome.transcript);

// 2) Quorum signs a membership credential
final partials = await collectPartials(officers, credentialBytes);
final rootSig = ThresholdSigner.combine(partials, outcome.publicKey);

// 3) Member device verifies with ordinary-style API
final ok = ThresholdSigner.verify(outcome.publicKey, credentialBytes, rootSig);
// or adapter into existing pqforge / app verifier
```

Transport, officer authentication, and secure storage are supplied by the application.

---

## 12. Anti-patterns in integration

| Anti-pattern | Consequence |
| -------------- | ------------- |
| Storing all shares on one server or one device | Destroys threshold guarantee |
| Letting the application server participate as a share-holder for the root | Server compromise becomes root compromise |
| Using threshold signing for every ordinary message | Unnecessary cost and operational friction |
| Skipping continuity proofs on rotation | Relying parties cannot safely migrate trust |
| Mixing shares from different ceremonies | Failures or silent security collapse |
| Reconstructing the root on a developer laptop “just once” | High exposure; treat as incident |

---

## 13. Summary

Integrate `pqthreshold` as the **distributed control plane** for roots and high-value signatures:

- **Generate** roots with dealer-less DKG ceremonies  
- **Attest** member keys and high-value actions with threshold signatures  
- **Operate** daily traffic with existing `pqforge` / `pqcrypto` single-party hybrid PQC  
- **Recover / rotate** only through explicit, transcribed ceremonies  
- **Keep** shares off the server and off any single device  

Done this way, the library completes the self-custody and enclave-isolation story without weakening the zero-knowledge or pure-Dart properties of the rest of the stack.

This document is the formative integration specification.  
Concrete adapters and example apps should reference the versioned public API of `pqthreshold` once it stabilizes.
