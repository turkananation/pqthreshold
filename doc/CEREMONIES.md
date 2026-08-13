# CEREMONIES.md

**pqthreshold** — Recommended multi-party flows for root generation, recovery, and rotation

Status: formative specification  
Audience: integrators, security reviewers, operators of enclave / organizational roots  
**Implementers:** [INDEX.md](INDEX.md)  
Prerequisites: `ARCHITECTURE.md`, `SECURITY.md`, [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md)

---

## 1. Purpose

Cryptographic primitives alone do not produce safe operational practice.  
This document defines **recommended ceremonies** — sequenced, auditable multi-party procedures that use `pqthreshold` to achieve concrete goals:

- Create an organizational or enclave root that no single party ever holds in full
- Recover control when devices or officers are lost
- Rotate keys while preserving continuity and audit evidence
- Refresh shares proactively (where the underlying scheme supports it)

Ceremonies are **patterns**, not mandatory APIs. Applications may call lower-level DKG / VSS / signing APIs directly. These flows encode the practices that keep the “no single point of secret” guarantee intact in real deployments.

---

## 2. Common definitions

| Term | Meaning |
| ------ | --------- |
| **Participant** | An authenticated party that holds (or will hold) a share |
| **Quorum** | Any set of at least `t` honest participants |
| **Dealer** | A party that starts with a secret and distributes shares (used only in dealer-based flows) |
| **Dealer-less** | DKG in which no party ever knows the full secret |
| **Transcript** | Hash-chained, serializable record of the ceremony’s public messages and outcomes |
| **Continuity proof** | Evidence linking a new public key to a prior one (e.g., signature by the old threshold key) |
| **Share bundle** | One participant’s private share plus the public verification material needed to use it |

All ceremonies assume:

1. Participants can authenticate one another (out of scope for `pqthreshold`)
2. Messages are carried over channels the application considers sufficiently confidential and integrity-protected for the threat model
3. Each participant protects its share at rest with appropriate platform security (secure storage, access control, etc.)

---

## 3. Ceremony principles

1. **Prefer dealer-less generation for roots**  
   Organizational and enclave roots should be born via DKG so the full private key never exists.

2. **Explicit quorum**  
   Every step that requires collaboration states `t` and `n` and fails closed if the quorum is not met.

3. **Transcript everything public**  
   Commitments, public shares, complaints, and final public keys belong in the transcript. Private shares never do.

4. **Separate generation from usage**  
   The ceremony that creates shares is distinct from day-to-day threshold signing.

5. **Recovery is deliberate**  
   Reconstruction of a full secret (when required) is a high-privilege, auditable event—not a background operation.

6. **Continuity is signed**  
   Rotations produce evidence that the new key is the authorized successor of the old one.

---

## 4. Ceremony catalog

| ID | Name | Goal | Typical threshold |
| ---- | ------ | ------ | ------------------- |
| C1 | Root DKG Ceremony | Create a new threshold root with no trusted dealer | 2-of-3, 3-of-5, 3-of-7, … |
| C2 | Dealer-based Sharing Ceremony | Split an existing secret (legacy or imported key) | same |
| C3 | Threshold Signing Ceremony | Produce a signature under the joint key | any `t`-of-`n` |
| C4 | Recovery / Reconstruction Ceremony | Reconstruct the secret or re-share under a new participant set | ≥ `t` |
| C4-B | Re-share without reconstruct | **v2** — not in initial release | ≥ `t` |
| C5 | Rotation Ceremony | Replace the threshold key while preserving continuity | ≥ `t` of old + new DKG |
| C6 | Share Refresh Ceremony | **v2** — proactive refresh without public key change | scheme-dependent |

---

## 5. C1 — Root DKG Ceremony (preferred for new roots)

### Goal

Generate a joint public key and per-participant private shares such that:

- No participant ever learns the full private key
- Any `t` shares can later sign or (if policy allows) reconstruct
- The process is publicly auditable via a transcript

### Preconditions

- Agreed `ThresholdParams` (`t`, `n`, scheme)
- Authenticated participant list of size `n`
- Secure channels between participants (application-provided)
- Each participant has a local `CeremonySession`

### Flow (logical rounds)

```text

Round 0  — Setup
  • All participants confirm params, identity set, and ceremony ID
  • Each creates a local CeremonySession

Round 1  — Contribution
  • Each participant generates local randomness and a commitment
  • Participants broadcast commitments (via application transport)
  • Sessions absorb peer commitments

Round 2  — Share distribution / complaints
  • Each participant distributes encrypted or pairwise shares to others
  • Participants verify received material
  • Complaints (if any) are broadcast and resolved per scheme rules

Round 3  — Finalization
  • Each participant derives its private Share
  • Joint PublicKey is computed and checked for consistency
  • Transcript is sealed

Output (per participant)
  • Private Share (to secure storage)
  • Joint PublicKey (public)
  • Transcript (archive)

```

### Success criteria

- All honest participants obtain the **same** PublicKey
- Each honest participant holds a distinct valid Share
- Transcript verifies
- Attempts to combine fewer than `t` shares fail

### Failure modes

- Missing participants beyond scheme tolerance → abort
- Inconsistent commitments or shares → abort, new ceremony ID required
- Transport or authentication failure → abort (library does not retry)

### Operational notes

- Run on offline or highly controlled machines when the root is high-value
- Record participant identities and the transcript in the organization’s audit log
- Never move private shares to general-purpose backup systems without additional encryption under a separate policy

---

## 6. C2 — Dealer-based Sharing Ceremony

### Goal

Split an **existing** secret (for example a legacy key being brought under threshold control) into `n` verifiable shares.

### When to use

- Migrating a single-party key to threshold control
- Importing a key generated elsewhere
- Situations where dealer-less DKG is unavailable for the required scheme

### Flow

```text

1. Dealer holds the secret and ThresholdParams
2. Dealer runs VSS → produces n Shares + public verification data
3. Dealer distributes one Share to each participant over authenticated channels
4. Each participant verifies its Share against the public verification data
5. Participants acknowledge receipt
6. Dealer securely deletes the original secret (policy-enforced)
7. Transcript records public verification data and participant set (not the secret)

```

### Critical rule

After successful distribution and acknowledgment, the dealer **must** wipe the full secret.  
If the dealer retains the secret, the threshold guarantee is void.

---

## 7. C3 — Threshold Signing Ceremony

### Goal

Produce a single ordinary signature on a message such that verification needs only the joint PublicKey.

### Flow

```text

1. Coordinator (or each signer) distributes the message and signing intent
2. Each participating share-holder produces a PartialSignature
3. At least t PartialSignatures are collected
4. Combiner runs ThresholdSigner.combine
5. Anyone may ThresholdSigner.verify(publicKey, message, signature)

```

### Rules

- Partial signatures from the wrong ceremony / public key are rejected
- Duplicate or inconsistent partials cause combination to fail closed
- The combined signature should be indistinguishable (at the verification API) from a normal single-party signature of the same type

### Usage pattern with pqforge

Applications may treat the combined signature as an ordinary signature for verification, envelope attestation, or continuity proofs.

---

## 8. C4 — Recovery / Reconstruction Ceremony

### Goal

Either:

- Reconstruct the full secret (rare, high-privilege), or
- Re-share under a new participant set without exposing the secret to a single party longer than necessary

### Preconditions

- At least `t` valid Shares
- Explicit authorization policy (out of band) to perform recovery
- Fresh ceremony ID

### Flow A — Full reconstruction (exceptional)

```text

1. Quorum of share-holders authenticate and agree on recovery intent
2. Shares are brought together in a controlled environment
3. reconstruct(shares) → Secret
4. Secret is used for the authorized purpose (e.g., one-time export, migration)
5. Secret is wiped
6. Transcript records that reconstruction occurred (never the secret itself)

```

### Flow B — Re-share to a new committee (v2)

> **v1 note:** Re-sharing without full reconstruction is deferred to v2. In v1, use controlled reconstruction (Flow A) under explicit policy, or run a new DKG (C5 rotation).

```text

1. Quorum reconstructs under controlled conditions **or** uses a scheme that supports re-sharing without full reconstruction
2. New ThresholdParams (possibly different t'/n') are chosen
3. New shares are distributed to the new participant set
4. Old shares are revoked / wiped under policy
5. Transcript links old PublicKey to new PublicKey if the public key changes

```

### Warning

Full reconstruction is the most dangerous operation in the system.  
It should be rare, multi-person, logged, and performed on air-gapped or equivalent machines when the key is high-value.

---

## 9. C5 — Rotation Ceremony

### Goal

Replace an existing threshold key with a new one while proving continuity.

### Flow

```text

1. Current quorum authorizes rotation (policy)
2. Run C1 (Root DKG) for the new params → new PublicKey + new Shares
3. Current quorum threshold-signs a continuity statement:
     “PublicKey_old authorizes PublicKey_new as successor at time T”
4. Distribute new Shares to the new (or same) participant set
5. Publish continuity proof + new PublicKey
6. Retire old Shares under policy after a grace period

```

### Continuity statement (conceptual)

```text

ContinuityProof {
  oldPublicKey,
  newPublicKey,
  ceremonyId,
  timestamp,
  thresholdSignature_over_above_fields
}

```

Verifiers that trust `oldPublicKey` can transitively trust `newPublicKey` after validating the proof.

---

## 10. C6 — Share Refresh Ceremony (v2)

> **Not in v1.** Use Rotation (C5) until proactive refresh is implemented.

### Goal

Update share material so that old shares become useless, without changing the joint PublicKey.  
This limits the damage of gradual share compromise.

### Availability

Only when the underlying scheme supports proactive refresh / share rotation.

### Flow (scheme-dependent)

```text

1. Participants run a refresh protocol
2. Each obtains a new Share bound to the same PublicKey
3. Old Shares are wiped
4. Transcript records that a refresh occurred

```

If the scheme does not support refresh, applications should schedule a full Rotation (C5) instead.

---

## 11. Participant lifecycle

| Event | Recommended action |
| ------- | -------------------- |
| Add participant | Prefer Rotation (C5) or re-share (C4-B) so the new party receives a fresh share; do not simply copy an existing share |
| Remove participant | Rotation or re-share to a committee that excludes the removed party; revoke old shares |
| Lost device | Treat the share as compromised; initiate Recovery or Rotation with remaining quorum |
| Suspected compromise | Immediate Refresh (if available) or Rotation; audit transcript |

Never “add” a participant by duplicating an existing share—that collapses the threshold.

---

## 12. Transcript requirements (all multi-party ceremonies)

A minimal transcript contains:

- Ceremony ID (unique)
- Scheme and `ThresholdParams`
- Ordered participant identities / public keys
- Hash chain of public messages
- Final PublicKey (if applicable)
- Outcome (success / abort reason)
- Timestamps (logical or wall-clock as appropriate)

Transcripts are public (or organization-internal) artifacts.  
They must never contain private shares or reconstructed secrets.

---

## 13. Mapping to library surfaces

| Ceremony | Primary library components | Protocol spec |
| -------- | -------------------------- | --------------- |
| C1 Root DKG | `dkg/`, `ceremony/`, `transcript/` | [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §3 |
| C2 Dealer sharing | `sharing/`, `transcript/` | [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §4 |
| C3 Threshold signing | `signing/` | [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §5 |
| C4 Recovery | `sharing/` (reconstruct), optionally `dkg/` + `ceremony/` | [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §4.4 |
| C5 Rotation | C1 + C3 (continuity signature) + `ceremony/` | [SERIALIZATION.md](SERIALIZATION.md) §4.6 |
| C6 Refresh | scheme-specific extension of `sharing/` or `dkg/` | v2 — not v1 |

---

## 14. Application responsibilities checklist

Before running any ceremony, the application must ensure:

- [ ] Participants are authenticated
- [ ] Channels provide integrity (and confidentiality appropriate to the threat model)
- [ ] `t` and `n` match policy
- [ ] Ceremony ID is unique
- [ ] Shares will be stored in secure storage after the ceremony
- [ ] Transcripts will be archived
- [ ] Abort paths leave no partial secrets on disk

`pqthreshold` enforces cryptographic rules; it cannot enforce organizational policy.

---

## 15. Anti-patterns

| Anti-pattern | Why it is dangerous |
| -------------- | --------------------- |
| Dealer generates a root and keeps a copy of the full key | Destroys the threshold guarantee |
| Copying one share to “add” a new participant | Reduces effective threshold |
| Reconstructing the secret on a general-purpose laptop for convenience | High exposure |
| Skipping transcripts | Loss of auditability |
| Reusing ceremony IDs | Replay and cross-ceremony confusion |
| Storing shares in ordinary files or cloud sync folders | Share compromise becomes trivial |

---

## 16. Summary

Ceremonies turn raw threshold primitives into repeatable, auditable operations:

- **C1** for birth of a root without a trusted dealer  
- **C2** for bringing legacy secrets under threshold control  
- **C3** for day-to-day quorum signatures  
- **C4** for deliberate recovery  
- **C5** for succession with continuity  
- **C6** for proactive share hygiene  

Followed carefully, they preserve the central invariant of `pqthreshold`:  
**after the ceremony, the full secret should not exist in any one place.**

This document is the formative specification for those flows.  
Round message byte layouts: [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md).  
Cryptographic profile: [FROST_PROFILE.md](FROST_PROFILE.md).
