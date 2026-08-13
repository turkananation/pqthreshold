# ARCHITECTURE.md

**pqthreshold** — High-assurance pure-Dart threshold cryptography & distributed key-management primitives

Status: formative specification  
Audience: implementers, reviewers, integrators  
Companion documents: `SECURITY.md`, `CEREMONIES.md`, `INTEGRATION.md`  
**Implementers:** [INDEX.md](INDEX.md)

---

## 1. Purpose and scope

`pqthreshold` supplies the cryptographic building blocks required to manage secrets that must never exist in full on a single device or under a single authority. It is intentionally narrow:

**In scope**

- Verifiable secret sharing (VSS)
- Distributed key generation (DKG) without a trusted dealer
- Threshold signature schemes (partial signing + combination)
- Ceremony-oriented helpers for root generation, recovery, and rotation
- Pure-Dart, zero-FFI implementations suitable for Dart VM, Flutter, and (where algorithmically feasible) web

**Out of scope**

- Network transport, participant authentication, or secure channels
- Full key-management systems, policy engines, or HSM abstractions
- General-purpose multi-party computation for arbitrary functions
- Post-quantum threshold schemes that are not yet stable enough for a high-assurance library surface (future work may revisit this)
- FIPS 140 / CMVP module claims

The library is designed to sit beside `pqcrypto` / `pqforge`: single-party hybrid post-quantum operations remain in those packages; distributed key control lives here.

---

## 2. Design principles

| Principle | Architectural consequence |
| ----------- | --------------------------- |
| No single point of secret | After a successful DKG or sharing ceremony, the full private key material is never reconstructed on one host except during an explicit, audited recovery path that itself requires a quorum |
| Pure Dart | All cryptographic operations use only the Dart SDK and carefully chosen pure-Dart dependencies (or in-tree implementations). No `dart:ffi`, no native plugins |
| Explicit thresholds | Every operation that depends on `t`-of-`n` takes an explicit `ThresholdParams` value; there are no hidden defaults that weaken the guarantee |
| Auditable transcripts | DKG and ceremony flows produce verifiable transcripts that can be logged or archived |
| Fail closed | Malformed shares, inconsistent verification data, or insufficient partial signatures produce sealed errors; they never yield partial or speculative secrets |
| Transport agnostic | The library never opens sockets or assumes a broadcast medium. Callers move messages between parties |
| Composability | Public keys and signatures produced by threshold operations are usable with ordinary verification paths (including those in `pqforge`) |

---

## 3. High-level component map

```

pqthreshold
├── params          ThresholdParams, security level, scheme identifiers
├── sharing         Verifiable secret sharing (share / verify / reconstruct)
├── dkg             Distributed key generation (round messages, transcript, output shares)
├── signing         Threshold signing (partial sign, combine, verify)
├── ceremony        Opinionated multi-party flows (root, recovery, rotation)
├── transcript      Serializable, hashable records of ceremony steps
├── errors          Sealed error hierarchy
└── util            Encoding, constant-time helpers, validation

```

Each top-level area is a separate library surface (or clearly bounded set of types) so that applications can depend only on what they need.

**Cross-cutting:** DKG and ceremony modules use **swissarmyknife** `StateMachine` and `Result`; cryptographic operations use **pqforge** (see `doc/SWISSARMYKNIFE.md`).

---

## 4. Core types (conceptual)

### 4.1 ThresholdParams

Immutable description of a threshold instance:

- `t` — minimum number of honest parties required
- `n` — total number of parties
- scheme identifier (which VSS / DKG / signature construction is in use)
- optional security-level or curve / field parameters

Validation rules (enforced at construction):

- `1 ≤ t ≤ n`
- `n` within documented maximums for the chosen scheme
- scheme-specific constraints (e.g., minimum `t` for certain constructions)

### 4.2 Share

Opaque, serializable holder of one party’s secret share plus public verification data.  
Shares are versioned and bound to a specific `ThresholdParams` and ceremony identifier so they cannot be mixed across ceremonies.

### 4.3 PublicKey / VerificationKey

The joint public key that results from DKG or from a sharing of an existing key.  
Verifiers need only this value; they do not need to know the threshold structure.

### 4.4 PartialSignature

Output of a single party’s signing operation on a message under its share.  
Insufficient or inconsistent partial signatures cannot be combined into a valid signature.

### 4.5 Transcript

Append-only, hash-chained record of ceremony messages and intermediate public values.  
Used for audit, debugging, and (where the scheme supports it) public verifiability of the DKG.

### 4.6 CeremonySession

Stateful helper that drives a multi-round protocol for a single participant.  
It accepts incoming messages, produces outgoing messages, and eventually yields a `Share` + `PublicKey` (or a failure).

---

## 5. Subsystem responsibilities

### 5.1 Verifiable Secret Sharing (sharing/)

Responsibilities:

- Split a secret into `n` shares such that any `t` shares reconstruct it and fewer than `t` reveal nothing
- Attach verification information so a recipient can detect a malformed or inconsistent share
- Reconstruct the secret only when a valid set of at least `t` shares is supplied
- Never log or expose the secret except through the explicit reconstruct API

Non-responsibilities:

- Distributing the shares (caller’s job)
- Authenticating the dealer (if a dealer exists) or the recipients

### 5.2 Distributed Key Generation (dkg/)

Responsibilities:

- Run a multi-round protocol in which each participant contributes randomness
- Produce a joint public key and per-participant private shares
- Guarantee that no coalition smaller than `t` can recover the joint private key
- Emit a transcript that allows later verification that the protocol was followed

Typical round structure (scheme-dependent):

1. Commitment / contribution of randomness
2. Share distribution / complaint phase
3. Finalization and public-key derivation

The library supplies per-participant state machines; the application supplies message transport and participant authentication.

### 5.3 Threshold Signing (signing/)

Responsibilities:

- Produce a partial signature from one share and a message
- Combine a quorum of partial signatures into a single ordinary signature
- Verify the combined signature against the joint public key
- Reject inconsistent or duplicate partial signatures

The combined signature should be verifiable by any party that possesses only the joint public key (including code that only depends on `pqforge` or standard signature verification).

### 5.4 Ceremony helpers (ceremony/)

Opinionated, higher-level flows built on the primitives:

- **RootCeremony** — generate an organizational / enclave root via DKG
- **RecoveryCeremony** — reconstruct or rotate using a quorum of shares
- **RotationCeremony** — move to a new threshold key while preserving continuity evidence
- **ShareRefresh** (where supported) — proactively refresh shares without changing the public key

These helpers encode recommended patterns; advanced users may call the lower-level APIs directly.

### 5.5 Transcript and audit

Every multi-party operation that accepts messages from others should be able to produce a transcript containing:

- Ceremony identifier
- Participant set (public identities or keys)
- Ordered messages (or hashes thereof)
- Final public outputs
- Hash chain so the transcript itself is tamper-evident

Transcripts are intended for archival and later audit, not for automatic network replay.

---

## 6. Data flow (happy path)

### 6.1 Distributed key generation

```text

Participant 1 … Participant n
        │
        ▼
  CeremonySession (local)
        │
        ├─ produce round-1 message
        │
        ▼
  [application transports messages]
        │
        ▼
  CeremonySession absorbs peer messages
        │
        ├─ produce round-2 / complaint messages
        │
        ▼
  … further rounds …
        │
        ▼
  Output: Share (private) + PublicKey (public) + Transcript

```

### 6.2 Threshold signing

```text

Message + Share  →  PartialSignature
                         │
                         ▼
        [collect ≥ t partial signatures]
                         │
                         ▼
              combine → Signature
                         │
                         ▼
              verify(PublicKey, Message, Signature)

```

### 6.3 Recovery / reconstruction

≥ t valid Shares  →  reconstruct → Secret (or new Share set)

Reconstruction is an explicit, high-privilege operation and should be gated by application policy.

---

## 7. Error model

All failures surface as a sealed hierarchy, for example:

- `ThresholdException`
  - `InvalidParams`
  - `InsufficientShares`
  - `InconsistentShares`
  - `InvalidPartialSignature`
  - `TranscriptMismatch`
  - `CeremonyAborted`
  - `SerializationError`

No API returns a partial secret or a “best-effort” key on error.  
Callers must handle the sealed types exhaustively.

---

## 8. Serialization and versioning

- All durable objects (`Share`, `PublicKey`, `PartialSignature`, `Transcript`, `ThresholdParams`) have an explicit format version
- Serialization is deterministic for the same logical value
- Domain separation is used so material from one ceremony or scheme cannot be interpreted as another
- Breaking format changes require a major version bump and migration notes

Recommended encoding: a compact binary format (e.g., CBOR or a simple length-prefixed layout) with a clear magic / version header. JSON may be offered for debugging only.

---

## 9. Security boundaries

| Boundary | Responsibility of pqthreshold | Responsibility of the application |
| ---------- | ------------------------------- | ----------------------------------- |
| Cryptographic correctness of VSS / DKG / threshold signatures | Yes | — |
| Participant authentication | No | Yes |
| Secure transport of messages and shares | No | Yes |
| Protection of shares at rest | No | Yes (secure storage, access control) |
| Choice of `t` and `n` | Validation only | Policy decision |
| Endpoint compromise | Out of scope | Out of scope |
| Side-channel resistance | Best-effort constant-time where practical in pure Dart | Additional hardening if required |

The library documents its assumptions clearly; it does not attempt to enforce assumptions that can only be upheld by the surrounding system.

---

## 10. Dependency and platform constraints

- **Runtime dependencies**: **two** — `pqforge` (crypto), `swissarmyknife` (structure). See `doc/SWISSARMYKNIFE.md`.
- **Dart SDK**: aligned with the same floor used by `pqforge` (`^3.12.x`).
- **Platforms**:
  - Dart VM / server — full support
  - Flutter mobile / desktop — full support
  - Web — supported where the underlying arithmetic remains practical; large-field or heavy schemes may be documented as VM-only
- **Isolates**: long-running DKG or signing operations should be safe to move to a background isolate; the library avoids global mutable state

---

## 11. Testing strategy

| Layer | Intent |
| ------- | -------- |
| Unit tests | Correctness of sharing, combination, verification, error paths |
| Known-answer / vector tests | Where published vectors exist for the chosen schemes |
| Property / randomized tests | Round-trip sharing, threshold boundaries (`t-1` must fail, `t` must succeed) |
| Transcript tests | Determinism and hash-chain integrity |
| Integration tests | Full DKG → sign → verify flows with simulated parties |
| Negative tests | Malformed shares, missing participants, replayed messages, inconsistent transcripts |

A release gate should refuse to publish if the core threshold invariants are not covered.

---

## 12. Extensibility

The architecture anticipates:

- Additional threshold signature schemes behind a common interface
- Optional hybrid post-quantum threshold constructions once the academic and standards picture stabilizes
- Share-refresh and proactive security extensions
- Tighter integration helpers for `pqforge` verification and Panthalassa-style enclave roots

New schemes must:

- Implement the same core traits / interfaces
- Provide clear security documentation
- Supply tests at the same standard as the initial schemes
- Preserve the “no single point of secret” and fail-closed properties

---

## 13. Directory layout (recommended)

```text
lib/
  pqthreshold.dart              # public barrel
  src/
    params/
    sharing/
    dkg/
    signing/
    ceremony/
    transcript/
    errors/
    util/
    scheme/
doc/
  INDEX.md                      # start here — reading order
  ARCHITECTURE.md               # this file
  SCHEMES.md
  PARAMS.md
  SERIALIZATION.md
  FROST_PROFILE.md
  PROTOCOL_MESSAGES.md
  API.md
  SWISSARMYKNIFE.md
  TEST_VECTORS.md
  SECURITY.md
  CEREMONIES.md
  INTEGRATION.md
  ROADMAP.md
  IMPLEMENTATION.md
  TOOLING.md
  RELEASE_CHECKLIST.md
  adr/
test/
  …
tool/
  verify.dart                   # optional release gate
```

---

## 14. Relationship to other packages

| Package | Relationship |
| --------- | -------------- |
| `pqcrypto` | Single-party PQC primitives; orthogonal |
| `pqforge` | Consumes ordinary signatures / public keys; can verify threshold-produced signatures |
| Application (Vault, etc.) | Owns transport, identity, policy, storage of shares, and user-facing ceremony UX |

`pqthreshold` never imports application code. Application code depends on `pqthreshold` (and optionally on `pqforge` / `pqcrypto`).

---

## 15. Architectural decisions (resolved for v1 implementation)

| # | Decision | Resolution | Record |
| - | -------- | ---------- | ------ |
| 1 | Threshold signature scheme(s) | FROST (Ed25519), combined sig = standard Ed25519 | `doc/SCHEMES.md`, ADR-001 |
| 2 | Dealer-based VSS vs dealer-less only | Both: Feldman VSS (C2) + Gennaro DKG (C1) | ADR-001 |
| 3 | Serialization format | Custom binary `PQTH` header + `PqBytes.lengthPrefixed` | `doc/SERIALIZATION.md`, ADR-003 |
| 4 | Constant-time in pure Dart | Best-effort via `PqBytes.constantTimeEquals`; document residual risk | `doc/SECURITY.md` §10 |
| 5 | Web support matrix | Ed25519/FROST supported; DKG soft limit `n ≤ 7` on web | `doc/SCHEMES.md` §6 |
| 6 | Low-level round messages vs ceremony-only | **Both tiers**: Tier 1 `CeremonySession` (production); Tier 2 simulation (tests) | `doc/API.md` |

Open for v2: proactive share refresh (C6), re-share without reconstruct (C4-B), Pedersen VSS.

---

## 16. Scheme plugin interface

Future schemes share a common seam under `lib/src/scheme/`:

- `ThresholdScheme` — params validation, scheme ID, platform limits
- `DkgProtocol` — round messages, session state, finalize
- `SigningProtocol` — partial sign, combine, verify
- `VssProtocol` — split, verify share, reconstruct

v1 implements only `frostEd25519V1`. New schemes require ADR + `doc/SCHEMES.md` update.

---

## 17. Summary

`pqthreshold` is a focused, pure-Dart library that turns “we need a key that no single party holds” into concrete, auditable primitives: verifiable sharing, distributed key generation, threshold signing, and ceremony helpers. It deliberately stops at the cryptographic boundary—transport, authentication, and policy remain the application’s responsibility—so that the same core can serve enclave roots, multi-officer approvals, and self-custodial recovery without pulling the rest of the stack into the library.

The architecture above is the formative specification against which implementations and reviews should be measured.
