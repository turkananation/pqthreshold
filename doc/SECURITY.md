# SECURITY.md

**pqthreshold** — Threat model, assumptions, claim boundaries, and secure usage requirements

Status: formative specification  
Audience: implementers, reviewers, integrators, operators  
**Implementers:** start at [INDEX.md](INDEX.md)  
Prerequisites: `ARCHITECTURE.md`, `CEREMONIES.md`, `INTEGRATION.md`

---

## 1. Purpose of this document

This file states **exactly what security properties `pqthreshold` claims**, what it does **not** claim, and what the surrounding application must uphold for those properties to hold in practice.

Threshold cryptography fails open in the real world when:

- shares are copied or stored insecurely  
- ceremonies are run without authenticating participants  
- reconstruction is treated as routine  
- transcripts are discarded  
- the application silently falls back to a weaker path  

The library can enforce cryptographic rules. It cannot enforce organizational discipline. This document draws that line clearly.

---

## 2. Security goals

When used as specified, `pqthreshold` aims to provide:

| Goal | Informal statement |
| ------ | -------------------- |
| **Confidentiality of the secret** | Any coalition of fewer than `t` participants learns nothing useful about the shared secret / private key |
| **Correctness of reconstruction** | Any set of `t` valid shares can reconstruct (where reconstruction is supported and authorized) |
| **Unforgeability of threshold signatures** | Only a quorum of honest share-holders can produce a combined signature that verifies under the joint public key |
| **Dealer-less generation** | In DKG flows, no party ever possesses the full private key |
| **Public verifiability of output** | The joint public key (and, where applicable, the transcript) can be checked for consistency |
| **Fail-closed behavior** | Malformed shares, insufficient partial signatures, or inconsistent transcripts produce errors—not partial secrets |

These goals are **cryptographic**. They hold only under the assumptions in §4.

---

## 3. Non-goals (explicit non-claims)

`pqthreshold` does **not**:

- Provide network transport, mutual authentication of participants, or secure channels  
- Protect against compromised participant devices (malware, shoulder surfing, evil maid)  
- Replace an HSM, QSCD, or FIPS 140 validated module  
- Claim CMVP / FIPS 140 validation for any algorithm  
- Guarantee availability (participants may refuse to show up)  
- Prevent a full quorum of colluding insiders from signing or reconstructing  
- Solve backup policy, legal custody, or multi-jurisdiction compliance by itself  
- Offer general-purpose MPC for arbitrary functions  
- Make pure-Dart arithmetic automatically constant-time against all side channels on all platforms  

If a property is not listed in §2, it is not claimed.

---

## 4. Assumptions

The security goals hold only if all of the following are true:

### 4.1 Cryptographic assumptions

- The underlying VSS / DKG / threshold signature constructions are secure under their stated hardness assumptions  
- Randomness used by participants is cryptographically secure (`Random.secure` or equivalent)  
- Parameters (`t`, `n`, scheme) are chosen within the supported and recommended ranges  

### 4.2 Participant and environment assumptions

- Participants are authenticated by the application before ceremony messages are accepted  
- Ceremony messages are protected by integrity (and confidentiality appropriate to the threat model) in transit  
- Each honest participant protects its private share at rest with platform-appropriate secure storage  
- Honest participants follow the protocol (do not leak shares, do not skip verification steps)  
- The application does not reconstruct the full secret except under explicit, audited policy  

### 4.3 Threshold assumption

- At most `t - 1` participants are dishonest or compromised  
- If `t` or more participants collude or are compromised, they can sign and (where enabled) reconstruct—this is by design  

### 4.4 Implementation assumptions

- The application uses the public APIs as documented and does not bypass validation  
- Serialization / deserialization only accepts versioned, domain-separated formats from trusted sources or verified transcripts  

Violation of any assumption voids the corresponding guarantee.

---

## 5. Threat model

### 5.1 Adversaries considered

| Adversary | Capabilities | Mitigations inside pqthreshold | Mitigations required outside |
| ----------- | -------------- | -------------------------------- | ------------------------------ |
| External network attacker | Observes or modifies traffic | None (no transport) | Authenticated, integrity-protected channels; encryption as needed |
| Malicious participant (< `t`) | Deviates from protocol, lies about shares | VSS verification, DKG complaints, fail-closed combine | Participant authentication; abort on complaints |
| Malicious quorum (≥ `t`) | Can sign / reconstruct | None (by design) | Organizational policy; split control; monitoring |
| Compromised device holding one share | Attacker obtains one share | Threshold still holds if < `t` shares leak | Secure storage; device hardening; rapid refresh/rotation |
| Curious or compromised application server | Reads server state | Shares never sent to server in recommended integration | Keep shares client-side only |
| Future quantum adversary | Breaks classical hardness | Use hybrid constructions at application layer with `pqcrypto` / `pqforge` for long-term assets | Combine threshold roots with post-quantum single-party keys where appropriate |
| Auditor / reviewer | Inspects code and transcripts | Transcripts, explicit params, open source | — |

### 5.2 Out of scope adversaries

- Physical extraction from unlocked devices under the owner’s control  
- Compelled disclosure of a full quorum of shares  
- Supply-chain compromise of the Dart toolchain or OS  
- Side-channel attacks beyond best-effort constant-time coding practices in pure Dart  

---

## 6. Claim boundaries (what you may and may not say)

### Allowed statements

- “Pure-Dart threshold cryptography primitives for VSS, DKG, and threshold signatures”
- “Designed so that fewer than `t` shares reveal nothing useful about the secret”
- “Dealer-less distributed key generation so the full private key never exists on one machine during generation”
- “Fail-closed combination of partial signatures”
- “Intended for organizational roots, enclave recovery, and multi-party approval workflows”

### Disallowed statements

- “FIPS certified” / “CMVP validated”
- “Quantum-safe threshold signatures” (unless a specific post-quantum threshold scheme is implemented and documented as such)
- “Secure against compromised endpoints”
- “Drop-in HSM replacement”
- “The server cannot be evil” (the server is outside this library; integration must keep shares off the server)
- “Production-ready for life-critical systems” without independent review and operational controls

Marketing and README language must stay inside the allowed set.

---

## 7. Parameter selection guidance

| Setting | Guidance |
| --------- | ---------- |
| `t` | Set by policy: how many independent officers must agree. Common choices: 2-of-3, 3-of-5, 3-of-7 |
| `n` | Number of currently trusted share-holders; plan for loss of devices |
| `t = 1` | Degenerates to single-party; allowed only for tests |
| `t = n` | Maximum collusion resistance; maximum availability risk |
| Very large `n` | May be impractical for interactive DKG; stay within documented scheme limits |

Wrong parameters are a policy failure, not a library failure. The library only validates structural constraints (`1 ≤ t ≤ n`, scheme limits).

---

## 8. Share lifecycle security

### 8.1 Generation

- Prefer dealer-less DKG (Ceremony C1) for roots  
- If dealer-based sharing is used, the dealer **must** wipe the full secret after distribution  

### 8.2 Storage

- Store each share in platform secure storage or equivalent  
- Never sync shares via ordinary cloud file sync  
- Never store all shares on one machine or one server  

### 8.3 Use

- Load shares only for the duration of a signing or recovery operation  
- Prefer `SecretBuffer` for temporary sensitive byte buffers and call
    `dispose()` in a `finally` block
- `SecretBuffer` takes ownership of its input, delegates wiping to
    `zeroize.SecretBytes`, and returns copies; callers must also dispose any
    sensitive copies they create
- Zeroization is best-effort in pure Dart: garbage-collector copies,
    immutable `BigInt` values, serialized buffers, and native/provider internals
    may retain material outside the managed buffer

### 8.4 Distribution and backup

- Treat a backup of a share as equivalent to the share itself  
- Encrypt share backups under a separate strong mechanism if offline backup is required  
- Document who holds which share  

### 8.5 Compromise response

- Assume a lost/stolen device compromises its share  
- With remaining honest quorum, run Refresh (C6) if available, otherwise Rotation (C5)  
- Revoke the old public key only after continuity is established  

### 8.6 Destruction

- On participant removal or rotation, wipe old shares under policy  
- Confirm wipe where the platform allows  

---

## 9. Ceremony security requirements

All multi-party ceremonies must:

1. Use a unique ceremony ID  
2. Authenticate participants before accepting messages  
3. Verify every share / commitment / partial signature as specified by the scheme  
4. Abort on inconsistency; do not “repair” silently  
5. Produce and archive a transcript of public data  
6. Never write private shares into the transcript or into logs  

Reconstruction (C4-A) additionally requires:

- Explicit multi-person authorization  
- Controlled environment (preferably air-gapped for high-value roots)  
- Immediate wipe of reconstructed secret after the authorized use  
- Audit record that reconstruction occurred  

---

## 10. Side channels and pure Dart

Pure Dart is not a constant-time language.  
`pqthreshold` will:

- Avoid data-dependent branches and table lookups in sensitive code paths where practical  
- Prefer algorithms and coding patterns known to reduce leakage  
- Document any known residual timing risk per scheme  

Applications with extreme side-channel requirements should:

- Run ceremonies on dedicated, controlled hardware  
- Consider additional physical and procedural controls  
- Not assume pure-Dart code matches assembly-level constant-time guarantees of native libraries  

---

## 11. Post-quantum posture

The initial scope of `pqthreshold` focuses on practical, well-understood threshold constructions for key management and signing.  

Long-term confidentiality and authenticity against quantum adversaries depend on the **application** combining:

- Threshold control of roots (this library)  
- Hybrid post-quantum single-party primitives for device keys and sealing (`pqcrypto` / `pqforge`)  

Do not claim “post-quantum threshold” unless a specific PQ threshold scheme is implemented, documented, and tested as such.

---

## 12. Dependency and supply-chain posture

- Prefer zero or minimal pure-Dart dependencies  
- Pin versions in application lockfiles  
- Run static analysis and the package test suite in CI  
- Review upstream changes before upgrading  
- Do not enable native plugins or FFI for this package  

---

## 13. Vulnerability reporting

Report suspected security issues privately according to [SECURITY.md](../SECURITY.md) at the repository root (GitHub Security Advisories or private reporting).

Please include:

- Affected version  
- Scheme / API involved  
- Minimal reproduction  
- Impact assessment (e.g., share recovery with < `t` shares, signature forgery without quorum)  

Do not open public issues for unfixed vulnerabilities.

---

## 14. Operational security checklist (operators)

Before production use of a threshold root:

- [ ] `t` and `n` match written policy  
- [ ] Participants are distinct people / devices with independent control  
- [ ] Shares live in secure storage on separate devices  
- [ ] Ceremony transcripts are archived  
- [ ] Reconstruction is forbidden except under documented emergency procedure  
- [ ] Rotation and continuity procedures are rehearsed  
- [ ] Server or backend never receives private shares  
- [ ] Combined signatures are verified before privileged actions are accepted  
- [ ] Loss of a device triggers refresh or rotation  

---

## 15. Summary of the security boundary

```text
                    ┌──────────────────────────────────────┐
                    │           Application / Ops          │
                    │  authn, transport, policy, storage,   │
                    │  UX, audit, recovery authorization   │
                    └──────────────────┬───────────────────┘
                                       │
                    ┌──────────────────▼───────────────────┐
                    │             pqthreshold              │
                    │  VSS · DKG · threshold sign ·        │
                    │  transcripts · fail-closed crypto    │
                    └──────────────────┬───────────────────┘
                                       │
                    ┌──────────────────▼───────────────────┐
                    │         Mathematical assumptions     │
                    │      + secure randomness + params    │
                    └──────────────────────────────────────┘
```

Everything above the library boundary is mandatory for real security and outside the library’s control.

---

## 16. Document control

- This SECURITY model is formative until version 1.0  
- Any change that weakens a claim in §2 or expands a non-claim in §3 requires a major version discussion  
- Scheme-specific assumptions for v1: **Appendix A** below  

**Bottom line:**  
`pqthreshold` gives you cryptographic tools so that a secret does not have to live in one place.  
It does not give you a complete secure system.  
The difference between those two statements is the difference between a useful library and a false sense of safety.

---

## Appendix A — Scheme-specific notes (`frostEd25519V1`)

**Profile:** [FROST_PROFILE.md](FROST_PROFILE.md)  
**Params:** [PARAMS.md](PARAMS.md)  
**Messages:** [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md)

### A.1 Assumptions

| Component | Assumption |
| --------- | ---------- |
| Feldman VSS | Discrete log on Ed25519; dealer honest at split time (C2) |
| Gennaro DKG | `< t` malicious participants; complaint phase exposes bad shares |
| FROST signing | `< t` corrupted signers; `{frostIdentifier}` binds roster and ceremony |
| Combined verify | RFC 8032 Ed25519 verification via `PqClassical.provider` |

### A.2 Known limitations

- **Not post-quantum** — organizational roots remain classical; hybridize at application layer ([INTEGRATION.md](INTEGRATION.md)).
- **Pure Dart timing** — see §10; scalar/point code may leak via timing on hostile OS.
- **Dealer C2** — dealer sees full secret during split; must wipe after distribution ([CEREMONIES.md](CEREMONIES.md) §6).
- **No ROAST** — identifiable abort not implemented; aborted signing requires new session.
- **max n = 255** — protocol limit ([PARAMS.md](PARAMS.md)); practical limits lower on web.

### A.3 Verification obligations (implementers)

- Reject all protocol messages with wrong `ceremonyId` or `scheme`.
- Enforce `senderIndex` in `1..n` ([PARAMS.md](PARAMS.md) §4).
- Use SHA-512 for FROST H1/H2/H3; SHA-256 for `messageBinding` ([FROST_PROFILE.md](FROST_PROFILE.md) §5, [SERIALIZATION.md](SERIALIZATION.md) §5).
- Run tests in [TEST_VECTORS.md](TEST_VECTORS.md) before claiming v1 readiness.
